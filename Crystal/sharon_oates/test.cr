require "http/server"
require "http/request"
require "http/server/response"


BIND_ADDRESS = "localhost"
PORT = 8080
TOP_DIR = __DIR__
PUBLIC_DIR = File.join(TOP_DIR, "public")


# I'm not a fan of handlers taking mutable Request and Response, but that's how Crystal's HTTP::Server works (as does Ruby's Rack).
# I'd prefer them to take a Request and Response in, and return a (possibly new) Request and Response.
# I may eventually override HTTP::Server to do that, but it'd take some effort to work with existing handlers.
# I suppose with HTTP/2, we should treat the request and response as streams, so maybe this does make some sense.
# I'm especially not a fan of handlers being required to call the next handler. But again, Rack does it this way too.
HANDLERS = [
  HTTP::ErrorHandler.new,
  HTTP::LogHandler.new(STDOUT),
  HTTP::StaticFileHandler.new(PUBLIC_DIR), # NOTE: This seems to try serving a file even if we've already output content. (Rack::Static does the same.)
  RouterHandler.new(TreeRouter),
  HTTP::DeflateHandler.new
]


# I *REALLY* wish Ruby and Crystal had this built in.
# Sometimes it just reads better this way than the other way around.
class Object
  def in?(collection)
    collection.includes?(self)
  end
end


class NotFound < Exception
end

class NotAllowedError < Exception
end


# Override this, or else you'll always get a 404, unless you break the handler chain.
# And if we want "after" handlers like DeflateHandler to work, we should never break the chain.
# I'd really like to rewrite the middleware stack, so handlers don't need to call the next handler in the chain.
# Instead, you'd set a special value within the context to indicate that the response has been completed.
# Following handlers would either check that a response has not been completed, or indicate that they will modify a response.
# The problem with this is that I don't think it'd handle "around" handlers, like ErrorHandler and LogHandler.
# The solution is probably to break handlers into "before", "after", and "around".
# Only "around" handlers would yield to the next handler.
# Maybe we could just check the signature (can we do that?), and if it takes a block, it's an around handler.
abstract class HTTP::Handler

  def call_next(context : HTTP::Server::Context)
    if next_handler = @next
      next_handler.call(context)
    else
      unless context.response.status_code
        context.response.status_code = 404
        context.response.headers["Content-Type"] = "text/plain"
        context.response.puts "Not Found"
      end
    end
  end

end


class RouterHandler < HTTP::Handler

  getter :router_type

  def initialize(@router_type : Class)
  end

  def call(context : HTTP::Server::Context)
    router_type.new(context).call
    call_next(context)
  end

end


module Router

  getter :context
  delegate :request, :context
  delegate :response, :context

  delegate :method, :request
  delegate :resource, :request
  delegate :path, :request
  delegate :query, :request
  delegate :query_params, :request
  delegate :headers, :request
  delegate :cookies, :request
  delegate :body, :request

  delegate "status_code=", :response

  def initialize(@context : HTTP::Server::Context)
  end

  def call
  end

  # We need to consider params as portions of the URL, URL query params, and parsing the body as JSON, XML, form-encoded, etc.
  # But for now, we only support URL query params.
  def params
    query_params
  end

end


class Artist

  getter :name

  def initialize(@name)
  end

end


class Album

  getter :name
  getter :artist

  def initialize(@name, @artist)
  end

end


module StaticRepo

  def list
    all
  end

  def get(id)
    if all.keys.includes?(id)
      all[id]
    else
      raise NotFound.new("Could not find item with key #{id} in #{self.class}")
    end
  end

end


class Artists

  include StaticRepo

  protected def all
    {
      1 => Artist.new("Genesis"),
      2 => Artist.new("Phil Collins")
    }
  end

end


class Albums

  include StaticRepo

  protected def all
    {
      1 => Album.new("Abacab", Artists.get(1)),
      2 => Album.new("No Jacket Required", Artists.get(2))
    }
  end

end


class TreeRouter

  include Router

  def call
    if path == "/"
      HomeController.new(context).call
    elsif path.to_s.starts_with?("/album")
      AlbumController.new(context).call
    elsif path.to_s.starts_with?("/artist")
      ArtistController.new(context).call
    else
      OtherController.new(context).call
    end
  end

end


module Controller

  include Router

  def call
    if method == "GET"
      if params && path.to_s.starts_with?("/artist")
        get(params["id"].to_i)
      else
        get
      end
    elsif method == "POST"
      post
    end
  end

  def get
    raise "Not implemented"
  end

  def get(id)
    raise "Not implemented"
  end

  def post
    raise "Not implemented"
  end

  protected def render_text(text)
    response.content_type = "text/plain"
    response.puts text
  end

  protected def render(filename, *args)
    response.content_type = "text/plain" # TODO: Base this on the filename.
    response.puts filename.read
  end

  protected def redirect_to_self
    redirect_to(".")
  end

  protected def redirect_to(url)
    response.headers["Location"] = url
    if request.version.in?(["HTTP/1.0", "HTTP/0.9"])
      response.status_code = 302
    else
      response.status_code = 303
    end
  end

end


class HomeController

  include Controller

  # GET /
  def get
    render_text "Hello, #{request.path}!"
#    render "index"
  end

  # GET /:id
  def get(id)
#    item = Items.get(id)
#    render "item", item
  end

  # POST /
  def post
#    Items.add(params)
    redirect_to_self
  end

  # DELETE /:id
  def delete(id)
#    Items.delete(id)
    redirect_to_self
  end

  # DELETE /
  def delete
    raise NotAllowedError # 405 (Method) Not Allowed
  end
end


class OtherController

  include Controller

  def get
    render_text "Goodbye, #{request.path}!"
  end

end


class ArtistController

  include Controller

  def get
    render_text "Artists:"
  end

  def get(id)
    result = ArtistOperation.new().get(id)
    # render_text result.class
    result.found     { |id, artist| render_text "Artist ##{id}: #{artist.name}" if artist }
    result.not_found { |id, artist| render_text "Artist ##{id}: NOT FOUND" }
  end

end


class AlbumController

  include Controller

  def get
    render_text "Albums:"
  end

  def get(id)
    render_text "Album ##{id}: TODO"
  end

end


# This is (kinda) stolen from https://github.com/BinaryNoggin/riposte, but reworked for Crystal.
class Response

  getter :response_type
  getter :params

  def initialize(@response_type, @params)
    print "Setting params for #{response_type}: "
    puts params
  end

  macro method_missing(call, &block)
    method_name = {{call.name.id.stringify}}
    if response_type.to_s == method_name
      puts "Correct callback called: #{response_type}"
      # Have to do this, due to Crystal not supporting `yield *params`. See https://github.com/manastech/crystal/issues/392.
      # But this breaks if we try to support more params than we're passed, due to type checking.
      case params.size
      when 0
        yield
      when 1
        yield params[0]
      when 2
        yield params[0], params[1]
      else
        raise "Don't support responses with more than 2 parameters"
      end
    end
    {{debug()}}
  end

end


module Operation

  def respond_with(response_type, *params)
    Response.new(response_type, params)
  end

end


class ArtistOperation

  include Operation

  def get(id)
    artist = Artists.new.get(id)
    respond_with(:found, id, artist)
  rescue NotFound
    respond_with(:not_found, id, nil)
  end

end


class OtherOperation

  include Operation

  def greet(name)

  end

end

# Here's what we'd like the router to look like:
#router_to_use = TreeRouter.new do
#  root RootController
#  resources_for_registered_controllers # Maybe. Hooks up any pulled-in controller as a resource controller.
#  resource "album", AlbumController
#  resource "artist", ArtistController
#  in "blah" do
#    method "GET" do
#      render_text "Hello!"
#    end
#    in "foo" do
#      render_text "bar"
#    end
#  end
#end


server = HTTP::Server.new(BIND_ADDRESS, PORT, HANDLERS)
puts "Listening on http://#{BIND_ADDRESS}:#{PORT}"
puts "Serving static files from #{PUBLIC_DIR}"
server.listen
