class Rosh
  class Users
    module ObjectAdapters
      module Base
        def self.included(base)
          base.extend ClassMethods
        end

        module ClassMethods
          def user_name=(user_name)
            @user_name = user_name
          end

          def host_name=(host_name)
            @host_name = host_name
          end
        end
      end
    end
  end
end
