package iomete.helpers.connection;

import org.apache.spark.sql.Row;
import org.apache.spark.sql.SparkSession;

import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

// Runs SQL over Spark Connect, the way an external client connects to a compute. Karate cannot
// speak gRPC itself. Called from features through Java.type.
public final class SparkConnectClient {

    private static volatile boolean sslConfigured = false;
    private static final String KEYSTORE_PASSWORD = "changeit";

    private SparkConnectClient() {}

    // Runs one statement and returns its rows keyed by column name, retrying a few times.
    public static List<Map<String, Object>> query(String url, String token, String sql)
            throws InterruptedException {
        return query(url, token, sql, null);
    }

    // Runs one statement with an optional custom SSL certificate (PEM file path).
    public static List<Map<String, Object>> query(String url, String token, String sql, String certPath)
            throws InterruptedException {
        configureSSL(certPath);
        return ClientAttempts.withRetries("spark connect", () -> run(url, token, sql));
    }

    // Returns why one attempt failed, or null when it succeeded.
    public static String failure(String url, String token, String sql) {
        return failure(url, token, sql, null);
    }

    // Returns why one attempt failed with an optional custom SSL certificate.
    public static String failure(String url, String token, String sql, String certPath) {
        configureSSL(certPath);
        return ClientAttempts.failure(() -> run(url, token, sql));
    }

    // Configures SSL to trust a custom certificate (PEM format) for Spark Connect connections.
    // This is called once per JVM; subsequent calls with the same or null certPath are no-ops.
    // Mirrors the Python example: https://github.com/iomete/spark-connect-quickstart/blob/main/example_custom_cert.py
    //
    // gRPC/Netty builds its own TLS context rather than using SSLContext.getDefault(), so we:
    // 1. Create a combined keystore with custom certs + JVM's effective default trust store
    // 2. Write it to a temp file
    // 3. Set javax.net.ssl.trustStore system properties (respected by gRPC-Netty with JDK SSL)
    private static synchronized void configureSSL(String certPath) {
        if (sslConfigured || certPath == null || certPath.isEmpty()) {
            return;
        }
        try {
            // Load all certificates from the PEM file (supports CA chain bundles)
            CertificateFactory cf = CertificateFactory.getInstance("X.509");
            Collection<? extends Certificate> customCerts;
            try (InputStream is = Files.newInputStream(Paths.get(certPath))) {
                customCerts = cf.generateCertificates(is);
            }
            if (customCerts.isEmpty()) {
                throw new RuntimeException("No certificates found in: " + certPath);
            }

            // Create a new keystore with the custom certificates
            KeyStore ks = KeyStore.getInstance(KeyStore.getDefaultType());
            ks.load(null, null);
            int certIndex = 0;
            for (Certificate cert : customCerts) {
                ks.setCertificateEntry("custom-ca-" + certIndex++, cert);
            }

            // Get the JVM's effective default trust managers (respects javax.net.ssl.trustStore if set)
            // and copy their trusted certificates into our keystore
            TrustManagerFactory defaultTmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
            defaultTmf.init((KeyStore) null); // null = use JVM's effective default trust store
            for (TrustManager tm : defaultTmf.getTrustManagers()) {
                if (tm instanceof X509TrustManager) {
                    X509TrustManager x509Tm = (X509TrustManager) tm;
                    for (X509Certificate cert : x509Tm.getAcceptedIssuers()) {
                        String alias = cert.getSubjectX500Principal().getName();
                        // Avoid duplicate aliases
                        if (!ks.containsAlias(alias)) {
                            ks.setCertificateEntry(alias, cert);
                        }
                    }
                }
            }

            // Write combined keystore to a temp file (gRPC/Netty reads from file, not in-memory)
            Path tempKeystore = Files.createTempFile("spark-connect-truststore-", ".jks");
            tempKeystore.toFile().deleteOnExit();
            try (FileOutputStream fos = new FileOutputStream(tempKeystore.toFile())) {
                ks.store(fos, KEYSTORE_PASSWORD.toCharArray());
            }

            // Set system properties that gRPC-Netty with JDK SSL provider respects
            System.setProperty("javax.net.ssl.trustStore", tempKeystore.toAbsolutePath().toString());
            System.setProperty("javax.net.ssl.trustStorePassword", KEYSTORE_PASSWORD);
            System.setProperty("javax.net.ssl.trustStoreType", KeyStore.getDefaultType());

            sslConfigured = true;
            System.out.println("[SparkConnectClient] SSL configured with " + customCerts.size() 
                + " custom certificate(s) from: " + certPath);
        } catch (Exception e) {
            throw new RuntimeException("Failed to configure SSL with certificate: " + certPath, e);
        }
    }

    private static List<Map<String, Object>> run(String url, String token, String sql) {
        SparkSession session = null;
        try {
            session = SparkSession.builder().remote(url.replace("{access_token}", token)).create();
            List<Map<String, Object>> rows = new ArrayList<>();
            for (Row row : session.sql(sql).collectAsList()) {
                Map<String, Object> values = new LinkedHashMap<>();
                String[] names = row.schema().fieldNames();
                for (int i = 0; i < names.length; i++) {
                    values.put(names[i], row.get(i));
                }
                rows.add(values);
            }
            return rows;
        } catch (Exception e) {
            // Scala rethrows checked exceptions undeclared, so catch them all here
            throw ClientAttempts.redacted(e, token);
        } finally {
            if (session != null) {
                try {
                    session.close();
                } catch (Exception ignored) {
                    // a session that never connected has nothing to release
                }
            }
        }
    }
}
