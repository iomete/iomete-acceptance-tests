// The JSON-RPC messages of a Server-Sent Events body, in order. An event ends at a blank line and
// may spread its data over several 'data:' lines, which join with a newline.
function(stream) {
  return stream.replace(/\r\n?/g, '\n').split('\n\n')
    .map(e => e.split('\n').filter(l => l.startsWith('data:')).map(l => l.substring(5).replace(/^ /, '')).join('\n'))
    .filter(data => data.length > 0)
    .map(data => JSON.parse(data));
}
