class Rosh
  class Host
    module PackageTypes

      # Represents a {http://www.rpm.org RPM package}.  Managed here using
      # {http://yum.baseurl.org Yum} and RPM commands.
      module Rpm

        # Result of <tt>yum info [pkg]</tt> as a Hash.
        #
        # @return [Hash]
        def info
          output = current_shell.exec "yum info #{@name}"
          info_hash = {}

          output.each_line do |line|
            %r[^(?<key>.*)\s*: (?<value>[^\n]*)\n$] =~ line

            if key && !key.strip.empty?
              info_hash[key.strip.to_safe_down_sym] = value.strip
            elsif value
              last_key = info_hash.keys.last
              info_hash[last_key] << " #{value.strip}"
            end
          end

          info_hash
        end

        # Uses <tt>yum info [pkg]</tt> to see if the package is installed
        # or not.
        #
        # @return [Boolean] +true+ if installed, +false+ if not.
        def installed?
          current_shell.exec "yum info #{@name}"

          current_shell.last_exit_status.zero?
        end

        # @return [Boolean] Checks to see if the latest installed version is
        #   the latest version available.
        def at_latest_version?
          cmd = "yum list updates #{@name}"
          result = current_shell.exec(cmd)

          # Could be that: a) not a package, b) the package is not installed, c)
          # the package is at the latest.
          if result =~ /No matching Packages to list/
            cmd = "yum info #{@name}"
            result = current_shell.exec(cmd)

            if result =~ /Available Packages/m
              false
            elsif result =~ %r[Installed Packages]
              true
            else
              nil
            end
          else
            if result =~ /updates/m
              false
            end
          end
        end

        # @return [String] The currently installed version of the package. +nil+
        #   if the package is not installed.
        def current_version
          cmd = "rpm -qa #{@name}"
          result = current_shell.exec(cmd)

          if result.empty?
            nil
          else
            %r[#{@name}-(?<version>\d\S*)] =~ result

            $~[:version] if $~
          end
        end

        private

        def default_bin_path
          '/usr/bin'
        end

        # Install the package.  If no +version+ is given, uses the latest in
        # Yum's cache.
        #
        # @param [String] version
        # @return [Boolean] +true+ if successful, +false+ if not.
        def install_package(version=nil)
          cmd = "yum install -y #{@name}"
          cmd << "-#{version}" if version
          current_shell.exec(cmd)

          current_shell.last_exit_status.zero?
        end

        # Upgrades the package, using <tt>yum upgrade [pkg]</tt>.
        #
        # @return [Boolean] +true+ if install was successful, +false+ if not.
        def upgrade_package
          output = current_shell.exec "yum upgrade -y #{@name}"
          success = current_shell.last_exit_status.zero?

          return false if output.match(/#{@name} available, but not installed/m)
          return false if output.match(/No Packages marked for Update/m)

          success
        end

        # Uses <tt>yum remove [pkg]</tt> to remove the package.
        #
        # @return [Boolean] +true+ if successful, +false+ if not.
        def remove_package
          current_shell.exec "yum remove -y #{@name}"

          current_shell.last_exit_status.zero?
        end
      end
    end
  end
end
