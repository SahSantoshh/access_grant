# frozen_string_literal: true

module AccessGrant
  # Validates and normalizes permission keys in +resource.action+ form.
  #
  # Pattern: +/\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/+
  class PermissionKey
    # @return [Regexp] enforced key shape
    PATTERN = /\A[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\z/

    # @param key [String, Symbol]
    # @return [Boolean]
    def self.valid?(key)
      PATTERN.match?(key.to_s)
    end

    # Coerce to String and validate.
    #
    # @param key [String, Symbol]
    # @return [String] normalized key
    # @raise [AccessGrant::Error] when the key is malformed
    def self.normalize!(key)
      normalized = key.to_s
      raise Error, "Invalid permission key: #{key.inspect}" unless valid?(normalized)

      normalized
    end
  end
end
