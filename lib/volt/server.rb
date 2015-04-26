ENV['SERVER'] = 'true'

require 'opal'

require 'rack'
require 'sass'
require 'volt/utils/tilt_patch'
require 'sprockets-sass'

require 'volt'
require 'volt/tasks/dispatcher'
require 'volt/tasks/task_handler'
require 'volt/server/component_handler'
require 'volt/server/rack/component_paths'
require 'volt/server/rack/index_files'
require 'volt/server/rack/http_resource'
require 'volt/server/rack/opal_files'
require 'volt/server/rack/quiet_common_logger'
require 'volt/page/page'

require 'volt/controllers/http_controller'
require 'volt/server/rack/http_request'
require 'volt/server/websocket/websocket_handler'
require 'volt/utils/read_write_lock'
require 'volt/server/forking_server'

module Rack
  # TODO: For some reason in Rack (or maybe thin), 304 headers close
  # the http connection.  We might need to make this check if keep
  # alive was in the request.
  class KeepAlive
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)

      if status == 304 && env['HTTP_CONNECTION'].downcase == 'keep-alive'
        headers['Connection'] = 'keep-alive'
      end

      [status, headers, body]
    end
  end
end

module Volt
  class Server
    attr_reader :listener, :app_path

    def initialize(root_path = nil)
      @root_path ||= Dir.pwd
      Volt.root = root_path

      @app_path        = File.expand_path(File.join(@root_path, 'app'))

      display_welcome
    end

    def display_welcome
      puts File.read(File.join(File.dirname(__FILE__), 'server/banner.txt'))
    end

    def boot_volt
      # Boot the volt app
      require 'volt/boot'

      @volt_app = Volt.boot(@root_path)
    end

    # App returns the main rack app.  In development it will fork a
    def app
      app = Rack::Builder.new

      # Handle websocket connections
      app.use WebsocketHandler

      if Volt.env.production?
        # In production, we boot the app and run the server
        boot_volt

        # Setup the dispatcher (it stays this class during its run)
        SocketConnectionHandler.dispatcher = Dispatcher.new
        app.run(new_server)
      else
        # In developer
        app.run ForkingServer.new(self)
      end

      app
    end

    # new_server returns the core of the Rack app.
    def new_server
      @rack_app = Rack::Builder.new

      # Should only be used in production
      if Volt.config.deflate
        @rack_app.use Rack::Deflater
        @rack_app.use Rack::Chunked
      end

      @rack_app.use Rack::ContentLength

      @rack_app.use Rack::KeepAlive
      @rack_app.use Rack::ConditionalGet
      @rack_app.use Rack::ETag

      @rack_app.use QuietCommonLogger
      @rack_app.use Rack::ShowExceptions

      component_paths = @volt_app.component_paths
      @rack_app.map '/components' do
        run ComponentHandler.new(component_paths)
      end

      # Serve the opal files
      opal_files = OpalFiles.new(@rack_app, @app_path, @volt_app.component_paths)

      # Serve the main html files from public, also figure out
      # which JS/CSS files to serve.
      @rack_app.use IndexFiles, @volt_app.component_paths, opal_files

      @rack_app.use HttpResource, @volt_app.router

      @rack_app.use Rack::Static,
        urls: ['/'],
        root: 'config/base',
        index: '',
        header_rules: [
          [:all, { 'Cache-Control' => 'public, max-age=86400' }]
        ]

      @rack_app.run lambda { |env| [404, { 'Content-Type' => 'text/html; charset=utf-8' }, ['404 - page not found']] }

      @rack_app
    end
  end
end
