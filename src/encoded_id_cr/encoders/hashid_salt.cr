module EncodedId
  module Encoders
    # Wrapper for the Hashid salt. Exposes both the original String and an
    # Array(String) of single-character strings (matching Ruby's `String#chars`).
    # Constructed once and treated as immutable thereafter.
    class HashidSalt
      getter salt : String
      getter chars : Array(String)

      def initialize(@salt : String)
        @chars = @salt.chars.map(&.to_s)
      end
    end
  end
end
