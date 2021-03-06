module Raibo
  class Bot
    attr_accessor :docs

    def initialize(*args)
      if args.first.is_a?(Raibo::CampfireConnection) or args.first.is_a?(Raibo::IrcConnection)
        @connection = args.shift
      elsif args.first == 'campfire'
        args.shift
        @connection = Raibo::CampfireConnection.new(*args)
      elsif args.first == 'irc'
        args.shift
        @connection = Raibo::IrcConnection.new(*args)
      end

      reset
    end

    def reset
      @handlers = []
      @docs = []
      @dsl = Raibo::DSL.new(self, @connection)

      use do |msg|
        if msg.body == '!help'
          @bot.help
        end
      end
    end

    def use(handler=nil, &block)
      @handlers.push(handler || block)
      @docs.concat(handler.docs) if handler.respond_to?(:docs)
    end

    def run(async=false)
      if async
        @thread = Thread.new { run_sync }
        @thread.abort_on_exception = true
      else
        run_sync
      end
    end

    def stop
      @thread.kill if @thread
      @connection.close
    end

    def alive?
      @thread.alive? if @thread
    end

    def load_config_file(filename)
      @dsl.instance_eval(IO.read(filename), filename)
    end

    def help
      width = [15, @docs.map(&:first).map(&:length).max].max

      @connection.say(*@docs.map { |cmd, desc| "%-#{width}s  %s" % [cmd, desc] })
    end

    private
      def run_sync
        @connection.open
        @connection.handle_lines do |line|
          message = @connection.construct_message(line)

          @handlers.each do |handler|
            begin
              if handler.is_a?(Proc)
                break if @dsl.instance_exec(message, &handler)
              else
                break if handler.call(@connection, message)
              end
            rescue Exception => e
              if @connection.verbose
                puts "Handler exception:\n  #{e.backtrace.join("\n  ")}"
              end
              @connection.say e.inspect
            end
          end
        end
      end
  end
end
