require 'openssl' 
require 'json'
require 'set'
require 'io/console'
require 'rubygems/package'

module Melon
  class Utils
    attr_accessor :data_hash, :iv # TODO: delete me

    def initialize(path: )
      file_exists = File.file?(path)
      @path = path

      if !file_exists 
        puts "Creating new melon - please enter a password:"
        @iv = OpenSSL::Cipher::AES256.new(:CBC).encrypt.random_iv
        @data_hash = {}
        get_password
        persist
        return
      end
      
      unpacked = unpack(path)
      @encrypted = unpacked[:secrets]
      @iv = unpacked[:nonce]
      puts "Melon found. Please type your password..."
      @data_hash = JSON.parse(
        decrypt(plain_password: get_password, data: @encrypted)
      )
    end

    def list
      @data_hash.keys
    end

    def put(key, value)
      @data_hash[key] = value
    end

    def get key 
      @data_hash.fetch(key, nil)
    end

    def encrypt
      @cipher = OpenSSL::Cipher::AES256.new(:CBC).encrypt

      @cipher.key = gen_key(@password || get_password)

      @iv = @cipher.random_iv # this assigns inside cipher
      # we can assign to @iv here because we wouldn't (hopefully!) be encrypted something
      # that is already encrypted
      @encrypted = @cipher.update(@data_hash.to_json) + @cipher.final
    end

    def decrypt(plain_password:, data:)
      decipher = OpenSSL::Cipher::AES256.new(:CBC)
      decipher.decrypt
      decipher.key = gen_key plain_password

      decipher.iv = @iv

      begin
        decipher.update(data) + decipher.final
      rescue OpenSSL::Cipher::CipherError => e
        puts "OpenSSL::Cipher::CipherError - incorrect password, most likely."
        exit 
      end
    end

    def changepwd
      get_password
    end

    #https://weblog.jamisbuck.org/2015/7/23/tar-gz-in-ruby.html
    def unpack(path)
      file_hash = {}
      File.open(path, "rb") do |file|
        Gem::Package::TarReader.new(file) do |tar|

          tar.each do |entry|
            if entry.full_name == 'nonce'
              file_hash[:nonce] = entry.read
            end
            if entry.full_name == 'secrets'
              file_hash[:secrets] = entry.read
            end
          end
    
          raise 'bad unpack!' unless file_hash.keys.to_set == Set[:secrets, :nonce]
        end
      end
      file_hash
    end

    def persist
      encrypt
      File.open(@path, "wb") do |file|
        Gem::Package::TarWriter.new(file) do |tar|

          tar.add_file_simple("secrets",
            0444, @encrypted.length
          ) do |io|
            io.write(@encrypted)
          end

          tar.add_file_simple("nonce",
            0444, @iv.length
          ) do |io|
            io.write(@iv)
          end
        end
      end

    end

    private

    def get_password
      @password = STDIN.noecho(&:gets)
    end

    def gen_key plain_password
      digestor = OpenSSL::Digest.new('sha256')
      digestor << plain_password
      digestor.digest    
    end

  end
end