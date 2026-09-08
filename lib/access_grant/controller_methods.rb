# frozen_string_literal: true

require "active_support/concern"
require "active_support/inflector"

module AccessGrant
  # Optional controller authorize hook (not a second Pundit).
  #
  # Maps +controller_name+ + +action_name+ → +resource.action+, then calls
  # {AccessGrant::User#permitted?} using configured current-user / tenant
  # methods. Include automatically via {AccessGrant::Railtie}.
  #
  # @example
  #   class ApplicationController < ActionController::Base
  #     access_grant_authorize!
  #     skip_access_grant_authorize! if: :devise_controller?
  #     rescue_from AccessGrant::NotAuthorizedError, with: :deny
  #   end
  module ControllerMethods
    extend ActiveSupport::Concern

    class_methods do
      # Install a +before_action+ that runs {#access_grant_authorize_request!}.
      #
      # @param options [Hash] forwarded to +before_action+ (e.g. +only:+, +except:+)
      # @return [void]
      def access_grant_authorize!(**options)
        if respond_to?(:before_action)
          before_action :access_grant_authorize_request!, **options
        else
          access_grant_authorize_callbacks << [:access_grant_authorize_request!, options]
        end
      end

      # Skip the authorize before_action.
      #
      # @param options [Hash] forwarded to +skip_before_action+
      # @return [void]
      def skip_access_grant_authorize!(**options)
        if respond_to?(:skip_before_action)
          skip_before_action :access_grant_authorize_request!, **options
        else
          access_grant_skip_authorize_callbacks << [:access_grant_authorize_request!, options]
        end
      end

      # @api private
      def access_grant_authorize_callbacks
        @access_grant_authorize_callbacks ||= []
      end

      # @api private
      def access_grant_skip_authorize_callbacks
        @access_grant_skip_authorize_callbacks ||= []
      end
    end

    # Authorize the current request. Raises {AccessGrant::NotAuthorizedError}
    # on deny, missing user, or {AccessGrant::Error} from +permitted?+.
    #
    # @return [void]
    # @raise [AccessGrant::NotAuthorizedError]
    def access_grant_authorize_request!
      user = send(AccessGrant.config.current_user_method)
      raise NotAuthorizedError, "No current user (#{AccessGrant.config.current_user_method})" if user.nil?

      key = access_grant_permission_key
      allowed =
        begin
          if access_grant_multi_tenant?
            tenant = send(AccessGrant.config.current_tenant_method)
            user.permitted?(key, tenant: tenant)
          else
            user.permitted?(key)
          end
        rescue Error => e
          raise NotAuthorizedError.new(e.message), cause: e
        end

      raise NotAuthorizedError, "Not authorized for #{key}" unless allowed
    end

    private

    def access_grant_permission_key
      "#{access_grant_resource_name}.#{action_name}"
    end

    def access_grant_resource_name
      name =
        if respond_to?(:controller_name) && !controller_name.nil?
          controller_name.to_s
        else
          self.class.name.demodulize.underscore.sub(/_controller\z/, "")
        end
      name.pluralize
    end

    def access_grant_multi_tenant?
      tenant_class = AccessGrant.config.tenant_class
      !(tenant_class.nil? || tenant_class.to_s.empty?)
    end
  end
end
