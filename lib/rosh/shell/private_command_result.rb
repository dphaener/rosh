require 'log_switch'


class Rosh
  class Shell

    # Used by adapters to convey the output of commands to the public
    # API so the public API can decide how to present the result.
    class PrivateCommandResult
      extend LogSwitch
      include LogSwitch::Mixin

      attr_reader :ruby_object
      attr_reader :exit_status
      attr_reader :executed_at

      def initialize(ruby_object, exit_status, as_string=nil)
        @ruby_object = ruby_object
        @exit_status = exit_status
        @string = as_string
        @executed_at = Time.now.to_s

        msg = "New result: ruby_object=#{@ruby_object}; "
        msg << "exit_status: #{@exit_status}; "
        msg << "string: #{@string}; "
        log msg
      end

      def string
        @string || @ruby_object.to_s
      end

      def string=(new_string)
        @string = new_string
      end

      # @return [Boolean] Tells if the result was an exception.  Exceptions are
      #   not representative of failed commands--they are, rather, most likely
      #   due to a problem with making the SSH connection.
      def exception?
        @ruby_object.kind_of?(Exception)
      end

      def failed?
        !@exit_status.zero?
      end
    end
  end
end

Rosh::Shell::PrivateCommandResult.log_class_name = true