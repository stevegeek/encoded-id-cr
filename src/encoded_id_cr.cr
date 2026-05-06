module EncodedId
  VERSION = "0.1.0"

  class Error < Exception; end
  class InvalidAlphabetError < Error; end
  class InvalidConfigurationError < Error; end
  class InvalidInputError < Error; end
  class EncodedIdFormatError < Error; end
  class EncodedIdLengthError < Error; end
end

require "./encoded_id_cr/alphabet"
require "./encoded_id_cr/char_helpers"
require "./encoded_id_cr/encoders/sqids"
require "./encoded_id_cr/reversible_id"
