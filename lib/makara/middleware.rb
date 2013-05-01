module Makara
  class Middleware

    def initialize(app)
      @app = app
    end

    def call(env)

      return @app.call(env) unless Makara.connection

      @request = Rack::Request.new(env)

      status, headers, body = if should_force_database?
                                Makara.connection.with_master do
                                  @app.call(env)
                                end
                              else
                                @app.call(env)
                              end

      @response = Rack::Response.new(body, status, headers)

      store_master_cookie!

      @response.finish

    ensure
      Makara.connection.try(:unstick!)
    end

    protected

    def should_force_database?
      database_to_force.present?
    end

    # currently just use master. flexibility coming soon.
    def database_to_force
      Makara.info("Database to force request")
      @request.cookies['makara-force-master']
    end

    def store_master_cookie!
      if @request.get?
        if [301, 302].include?(@response.status.to_i)
          Makara.info ("Redirect, skipping cookie delete")
          return
        end

        if @response.header['Set-Cookie'].present?
          Makara.info ("Deleting force master cookie")
          @response.delete_cookie('makara-force-master')
        end
      elsif Makara.connection.sticky_master? && Makara.connection.currently_master?
        ttl = Time.at(Time.now.to_i + 5)
        Makara.info ("Setting makara cookie value to #{ Makara.connection.current_wrapper_name}")

        @response.set_cookie('makara-force-master', {:value => Makara.connection.current_wrapper_name, :expires => ttl})
      end
    end

  end
end