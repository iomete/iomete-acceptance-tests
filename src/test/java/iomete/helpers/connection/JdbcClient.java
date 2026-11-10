package iomete.helpers.connection;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.logging.Level;
import java.util.logging.Logger;

// Runs SQL over JDBC, the way an external client connects to a compute. Karate cannot speak
// Thrift or Arrow Flight itself. Called from features through Java.type.
public final class JdbcClient {

    private static final int LOGIN_TIMEOUT_SECONDS = 30;
    private static final int QUERY_TIMEOUT_SECONDS = 60;

    // Arrow's driver logs through java.util.logging, which logback does not reach. Held in a
    // field so the setting is not garbage collected with the logger.
    private static final Logger ARROW_LOGGER =
            Logger.getLogger("org.apache.arrow.driver.jdbc.shaded");

    static {
        ARROW_LOGGER.setLevel(Level.OFF);
    }

    private JdbcClient() {}

    // Runs one statement and returns its rows keyed by column label, retrying a few times.
    public static List<Map<String, Object>> query(String url, String user, String token, String sql)
            throws InterruptedException {
        return ClientAttempts.withRetries("jdbc", () -> run(url, user, token, sql));
    }

    // Returns why one attempt failed, or null when it succeeded.
    public static String failure(String url, String user, String token, String sql) {
        return ClientAttempts.failure(() -> run(url, user, token, sql));
    }

    private static List<Map<String, Object>> run(
            String url, String user, String token, String sql) {
        // the backend writes the token placeholder as either {access_token} or {password}
        String filledUrl =
                url.replace("{user}", user)
                        .replace("{access_token}", token)
                        .replace("{password}", token);
        Properties props = new Properties();
        props.setProperty("user", user);
        props.setProperty("password", token);
        DriverManager.setLoginTimeout(LOGIN_TIMEOUT_SECONDS);
        try (Connection connection = DriverManager.getConnection(filledUrl, props);
                Statement statement = connection.createStatement()) {
            statement.setQueryTimeout(QUERY_TIMEOUT_SECONDS);
            ResultSet resultSet = statement.executeQuery(sql);
            ResultSetMetaData meta = resultSet.getMetaData();
            List<Map<String, Object>> rows = new ArrayList<>();
            while (resultSet.next()) {
                Map<String, Object> row = new LinkedHashMap<>();
                for (int i = 1; i <= meta.getColumnCount(); i++) {
                    row.put(meta.getColumnLabel(i), resultSet.getObject(i));
                }
                rows.add(row);
            }
            return rows;
        } catch (SQLException | RuntimeException e) {
            throw ClientAttempts.redacted(e, token);
        }
    }
}
