module RocketAMF
  # Container for the AMF request/response.
  class Envelope
    attr_reader :amf_version, :headers, :messages

    def initialize props={}
      @amf_version = props[:amf_version] || 0
      @headers = props[:headers] || {}
      @messages = props[:messages] || []
    end

    # Populates the envelope from the given stream or string using the given
    # class mapper, or creates a new one. Returns self for easy chaining.
    #
    # Example:
    #
    #    req = RocketAMF::Envelope.new.populate_from_stream(env['rack.input'].read)
    #--
    # Implemented in pure/remoting.rb RocketAMF::Pure::Envelope
    def populate_from_stream stream, class_mapper=nil
      raise AMFError, 'Must load "rocketamf/pure"'
    end

    # Serializes the envelope to a string using the given class mapper, or creates
    # a new one, and returns the result
    #--
    # Implemented in pure/remoting.rb RocketAMF::Pure::Envelope
    def serialize class_mapper=nil
      raise AMFError, 'Must load "rocketamf/pure"'
    end

    # Builds response from the request, iterating over each method call and using
    # the return value as the method call's return value
    #--
    # Iterate over all the sent messages. If they're somthing we can handle, like
    # a command message, then simply add the response message ourselves. If it's
    # a method call, then call the block with the method and args, catching errors
    # for handling. Then create the appropriate response message using the return
    # value of the block as the return value for the method call.
    def each_method_call request, &block
      raise 'Response already constructed' if @constructed

      # Set version from response
      # Can't just copy version because FMS sends version as 1
      @amf_version = request.amf_version == 3 ? 3 : 0 

      request.messages.each do |m|
        # What's the request body?
        case m.data
        when Values::CommandMessage
          # Pings should be responded to with an AcknowledgeMessage built using the ping
          # Everything else is unsupported
          command_msg = m.data
          if command_msg.operation == Values::CommandMessage::CLIENT_PING_OPERATION
            response_value = Values::AcknowledgeMessage.new(command_msg)
          else
            e = Exception.new("CommandMessage #{command_msg.operation} not implemented")
            e.set_backtrace ["RocketAMF::Envelope each_method_call"]
            response_value = Values::ErrorMessage.new(command_msg, e)
          end
        when Values::RemotingMessage
          # Using RemoteObject style message calls
          remoting_msg = m.data
          acknowledge_msg = Values::AcknowledgeMessage.new(remoting_msg)
          method_base = remoting_msg.source.to_s.empty? ? '' : remoting_msg.source+'.'
          body = dispatch_call :method => method_base+remoting_msg.operation, :args => remoting_msg.body, :source => remoting_msg, :block => block

          # Response should be the bare ErrorMessage if there was an error
          if body.is_a?(Values::ErrorMessage)
            response_value = body
          else
            acknowledge_msg.body = body
            response_value = acknowledge_msg
          end
        else
          # Standard response message
          response_value = dispatch_call :method => m.target_uri, :args => m.data, :source => m, :block => block
        end

        target_uri = m.response_uri
        target_uri += response_value.is_a?(Values::ErrorMessage) ? '/onStatus' : '/onResult'
        @messages << ::RocketAMF::Message.new(target_uri, '', response_value)
      end

      @constructed = true
    end

    # Whether or not the response has been constructed. Can be used to prevent
    # serialization when no processing has taken place.
    def constructed?
      @constructed
    end

    # Return the serialized envelope as a string
    def to_s
      serialize
    end

    def dispatch_call p #:nodoc:
      begin
        p[:block].call(p[:method], p[:args])
      rescue Exception => e
        # Create ErrorMessage object using the source message as the base
        Values::ErrorMessage.new(p[:source], e)
      end
    end
  end

  # RocketAMF::Envelope header
  class Header
    attr_accessor :name, :must_understand, :data

    def initialize name, must_understand, data
      @name = name
      @must_understand = must_understand
      @data = data
    end
  end

  # RocketAMF::Envelope message
  class Message
    attr_accessor :target_uri, :response_uri, :data

    def initialize target_uri, response_uri, data
      @target_uri = target_uri
      @response_uri = response_uri
      @data = data
    end
  end
end