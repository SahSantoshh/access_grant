# frozen_string_literal: true

RSpec.describe AccessGrant::ControllerMethods do
  let(:controller_class) do
    Class.new do
      class << self
        attr_accessor :before_actions, :skipped_before_actions

        def before_action(method_name, **options)
          (@before_actions ||= []) << [method_name, options]
        end

        def skip_before_action(method_name, **options)
          (@skipped_before_actions ||= []) << [method_name, options]
        end
      end

      include AccessGrant::ControllerMethods

      attr_accessor :controller_name, :action_name, :current_user, :current_tenant,
                    :current_account, :current_organization
    end
  end

  let(:controller) { controller_class.new }

  before do
    AccessGrant.reset_config!
    controller_class.before_actions = nil
    controller_class.skipped_before_actions = nil
  end

  after { AccessGrant.reset_config! }

  describe ".access_grant_authorize!" do
    it "installs a before_action for :access_grant_authorize_request!" do
      controller_class.access_grant_authorize!

      expect(controller_class.before_actions).to eq([
                                                      [:access_grant_authorize_request!, {}]
                                                    ])
    end

    it "forwards options to before_action" do
      controller_class.access_grant_authorize!(only: :index)

      expect(controller_class.before_actions).to eq([
                                                      [:access_grant_authorize_request!, { only: :index }]
                                                    ])
    end
  end

  describe ".skip_access_grant_authorize!" do
    it "skips the authorize before_action" do
      controller_class.skip_access_grant_authorize!(if: :devise_controller?)

      expect(controller_class.skipped_before_actions).to eq([
                                                              [:access_grant_authorize_request!,
                                                               { if: :devise_controller? }]
                                                            ])
    end
  end

  describe "#access_grant_authorize_request!" do
    context "permission key mapping" do
      it "maps invoices#index to invoices.index" do
        user = double("User")
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user

        expect(user).to receive(:permitted?).with("invoices.index").and_return(true)

        controller.access_grant_authorize_request!
      end

      it "maps invoices#couple to invoices.couple" do
        user = double("User")
        controller.controller_name = "invoices"
        controller.action_name = "couple"
        controller.current_user = user

        expect(user).to receive(:permitted?).with("invoices.couple").and_return(true)

        controller.access_grant_authorize_request!
      end

      it "pluralizes a singular controller_name" do
        user = double("User")
        controller.controller_name = "invoice"
        controller.action_name = "show"
        controller.current_user = user

        expect(user).to receive(:permitted?).with("invoices.show").and_return(true)

        controller.access_grant_authorize_request!
      end

      it "derives resource from class name when controller_name is absent" do
        bare = Class.new do
          class << self
            def before_action(*) = nil
            def skip_before_action(*) = nil
            def name = "InvoicesController"
          end

          include AccessGrant::ControllerMethods

          attr_accessor :action_name, :current_user
        end.new

        user = double("User")
        bare.action_name = "index"
        bare.current_user = user

        expect(user).to receive(:permitted?).with("invoices.index").and_return(true)

        bare.access_grant_authorize_request!
      end
    end

    context "current_user / current_tenant resolution" do
      it "uses config.current_user_method" do
        AccessGrant.configure { |c| c.current_user_method = :current_account }

        user = double("User")
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_account = user

        expect(user).to receive(:permitted?).with("invoices.index").and_return(true)

        controller.access_grant_authorize_request!
      end

      it "passes tenant from config.current_tenant_method when multi-tenant" do
        AccessGrant.configure do |c|
          c.tenant_class = "Organization"
          c.current_tenant_method = :current_organization
        end

        user = double("User")
        tenant = double("Organization")
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user
        controller.current_organization = tenant

        expect(user).to receive(:permitted?).with("invoices.index", tenant: tenant).and_return(true)

        controller.access_grant_authorize_request!
      end

      it "omits tenant when single-tenant" do
        AccessGrant.configure { |c| c.tenant_class = nil }

        user = double("User")
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user
        controller.current_tenant = double("should-not-be-used")

        expect(user).to receive(:permitted?).with("invoices.index").and_return(true)

        controller.access_grant_authorize_request!
      end
    end

    context "failures" do
      it "raises NotAuthorizedError when permitted? is false" do
        user = double("User", permitted?: false)
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user

        expect do
          controller.access_grant_authorize_request!
        end.to raise_error(AccessGrant::NotAuthorizedError)
      end

      it "raises NotAuthorizedError when current user is nil" do
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = nil

        expect do
          controller.access_grant_authorize_request!
        end.to raise_error(AccessGrant::NotAuthorizedError, /current user/i)
      end

      it "maps permitted? AccessGrant::Error to NotAuthorizedError" do
        user = double("User")
        allow(user).to receive(:permitted?).and_raise(
          AccessGrant::Error, "Unknown permission key: \"invoices.index\""
        )
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user

        expect do
          controller.access_grant_authorize_request!
        end.to raise_error(AccessGrant::NotAuthorizedError, 'Unknown permission key: "invoices.index"') do |error|
          expect(error.cause).to be_a(AccessGrant::Error)
          expect(error.cause).not_to be_a(AccessGrant::NotAuthorizedError)
        end
      end

      it "maps nil-tenant permitted? Error to NotAuthorizedError when multi-tenant" do
        AccessGrant.configure do |c|
          c.tenant_class = "Organization"
          c.current_tenant_method = :current_organization
        end

        user = double("User")
        allow(user).to receive(:permitted?).with("invoices.index", tenant: nil).and_raise(
          AccessGrant::Error, "tenant: is required in multi-tenant mode"
        )
        controller.controller_name = "invoices"
        controller.action_name = "index"
        controller.current_user = user
        controller.current_organization = nil

        expect do
          controller.access_grant_authorize_request!
        end.to raise_error(AccessGrant::NotAuthorizedError, "tenant: is required in multi-tenant mode")
      end

      it "makes NotAuthorizedError a subclass of AccessGrant::Error" do
        expect(AccessGrant::NotAuthorizedError < AccessGrant::Error).to be(true)
      end
    end
  end
end
