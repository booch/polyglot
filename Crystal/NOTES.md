Crystal Notes
=============

HTTP::Server
------------

~~~ crystal
# A very basic HTTP server
require "http/server"

server = HTTP::Server.new(8080) do |context|
  context.response.content_type = "text/plain"
  context.response.print "Hello world, got #{context.request.path}!"
end

puts "Listening on http://0.0.0.0:8080"
server.listen
~~~


PG
--

DB = PG.connect("postgres://...")
result = DB.exec({Int32, String}, "select id, email from users")
result.fields  #=> [PG::Result::Field, PG::Result::Field]
result.rows    #=> [{1, "will@example.com"}], …]
result.to_hash #=> [{"field1" => value, …}, …]

result = DB.exec({String}, "select $1::text || ' ' || $2::text", ["hello", "world"])
result.rows #=> [{"hello world"}]
