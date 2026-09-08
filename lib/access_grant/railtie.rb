# frozen_string_literal: true

module AccessGrant
  # Rails integration: loads rake tasks and includes {ControllerMethods} on
  # Action Controller.
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/access_grant_tasks.rake", __dir__)
    end

    initializer "access_grant.action_controller" do
      ActiveSupport.on_load(:action_controller) do
        include AccessGrant::ControllerMethods
      end
    end
  end
end
