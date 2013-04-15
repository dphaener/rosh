class Rosh
  class Host
    module PackageTypes

      class Brew
        attr_reader :name

        def initialize(shell, name)
          @shell = shell
          @name = name
        end

        # @return [String]
        def info
          @shell.exec "brew info #{@name}"
        end

        # @return [Boolean] +true+ if install was successful; +false+ if not.
        def install
          @shell.exec "brew install #{@name}"

          @shell.history.last[:exit_status].zero?
        end

        # @return [Boolean]
        def installed?
          result = @shell.exec "brew info #{@name}"

          !result.match /Not installed/
        end

        # @param [Boolean] force
        def remove(force: false)
          cmd = "brew remove #{@name}"
          cmd << ' --force' if force
          @shell.exec(cmd)

          @shell.history.last[:exit_status].zero?
        end
      end
    end
  end
end
