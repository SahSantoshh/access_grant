# frozen_string_literal: true

require "active_record"
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.connection.verify!
ActiveRecord::Base.logger = Logger.new(IO::NULL)
