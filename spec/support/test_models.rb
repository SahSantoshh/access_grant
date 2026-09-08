# frozen_string_literal: true

class Organization < ActiveRecord::Base
  self.table_name = "organizations"
  access_grant :tenant
end

class User < ActiveRecord::Base
  self.table_name = "users"
  access_grant :user
end
