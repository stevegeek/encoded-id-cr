module EncodedId
  VERSION = "0.1.0"

  class Error < Exception; end

  class InvalidAlphabetError < Error; end

  class InvalidConfigurationError < Error; end

  class InvalidInputError < Error; end

  class EncodedIdFormatError < Error; end

  class EncodedIdLengthError < Error; end

  class SaltError < Error; end

  class BlocklistError < Error; end
end

require "./encoded_id_cr/alphabet"
require "./encoded_id_cr/blocklist"
require "./encoded_id_cr/char_helpers"
require "./encoded_id_cr/hex_representation"
require "./encoded_id_cr/encoders/sqids"
require "./encoded_id_cr/encoders/hashid_salt"
require "./encoded_id_cr/encoders/hashid_consistent_shuffle"
require "./encoded_id_cr/encoders/hashid_ordinal_alphabet_separator_guards"
require "./encoded_id_cr/encoders/hashid"
require "./encoded_id_cr/reversible_id"
