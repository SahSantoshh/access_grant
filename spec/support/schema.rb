# frozen_string_literal: true

tables = AccessGrant.config.tables

ActiveRecord::Schema.define do
  create_table tables.fetch(:permissions), force: true do |t|
    t.string :key, null: false
    t.text :description
    t.string :category
    t.timestamps
  end
  add_index tables.fetch(:permissions), :key, unique: true
  add_index tables.fetch(:permissions), %i[category key]

  create_table tables.fetch(:roles), force: true do |t|
    t.string :name, null: false
    t.text :description
    t.bigint :tenant_id
    t.timestamps
  end
  add_index tables.fetch(:roles), %i[tenant_id name], unique: true
  add_index tables.fetch(:roles), :name

  create_table tables.fetch(:role_permissions), force: true do |t|
    t.references :role, null: false, foreign_key: { to_table: tables.fetch(:roles) }
    t.references :permission, null: false, foreign_key: { to_table: tables.fetch(:permissions) }
    t.timestamps
  end
  add_index tables.fetch(:role_permissions), %i[role_id permission_id], unique: true

  create_table :users, force: true, &:timestamps

  create_table :organizations, force: true, &:timestamps

  create_table tables.fetch(:user_roles), id: false, force: true do |t|
    t.bigint :user_id, null: false
    t.bigint :role_id, null: false
  end
  add_index tables.fetch(:user_roles), %i[user_id role_id], unique: true
  add_index tables.fetch(:user_roles), :role_id
end

RSpec.configure do |config|
  config.around do |example|
    ActiveRecord::Base.connection.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
