require 'rest-client'
require 'json'
require 'openssl'
require 'base64'
require 'open-uri'
require_relative 'epayco/resources'

module Epayco

  # Set custom error
  class Error < StandardError
    include Enumerable
    attr_accessor :errors

    # Get code, lang and show custom error
    def initialize code, lang
      file = open("https://s3-us-west-2.amazonaws.com/epayco/message_api/errors.json").read
      data_hash = JSON.parse(file)
      super data_hash[code][lang]
      @errors = errors
    end

    def each
      @errors.each { |e| yield *e.first }
    end
  end

  # Endpoints
  @api_base = 'http://localhost:3000'
  @api_base_secure = 'https://secure.payco.co'

  # Init sdk parameters
  class << self
     attr_accessor :apiKey, :privateKey, :lang, :test
  end

  # Eject request and show response or error
  def self.request(method, url, extra=nil, params={}, headers={}, switch)
    method = method.to_sym


    unless apiKey ||= @apiKey
      raise Error.new('100', lang)
    end

    unless privateKey ||= @privateKey
      raise Error.new('100', lang)
    end

    payload = JSON.generate(params) if method == :post || method == :patch
    params = nil unless method == :get

    # Switch secure or api
    if switch
      if method == :post || method == :patch
        enc = encrypt_aes(payload)
        payload = enc.to_json
      end
      url = @api_base_secure + url
    else
      url = @api_base + url
    end

    headers = {
      :params => params,
      :content_type => 'application/json',
      :type => 'sdk'
    }.merge(headers)

    options = {
      :headers => headers,
      :user => apiKey,
      :method => method,
      :url => url,
      :payload => payload
    }

    # Open library rest client
    begin
      response = execute_request(options)
      return {} if response.code == 204 and method == :delete
      JSON.parse(response.body, :symbolize_names => true)
    rescue RestClient::Exception => e
      handle_errors e
    end
  end

  private

  # Get response successful
  def self.execute_request(options)
    RestClient::Request.execute(options)
  end

  # Get response with errors
  def self.handle_errors exception
    body = JSON.parse exception.http_body
    raise Error.new(exception.to_s, body['errors'])
  end

  def self.encrypt_aes data
    sandbox = Epayco.test ? "TRUE" : "FALSE"
    @tags = JSON.parse(data)
    @seted = {}
    @tags.each {
      |key, value|
      @seted[lang_key(key)] = encrypt(value, Epayco.privateKey)
    }
    @seted["public_key"] = Epayco.apiKey
    @seted["i"] = Base64.encode64("0000000000000000")
    @seted["enpruebas"] = encrypt(sandbox, Epayco.privateKey)
    @seted["lenguaje"] = "ruby"
    @seted["p"] = ""
    return @seted
  end

  def self.encrypt(str, key)
    cipher = OpenSSL::Cipher.new('AES-128-CBC')
    cipher.encrypt
    iv = "0000000000000000"
    cipher.iv = iv
    cipher.key = key
    str = iv + str
    data = cipher.update(str) + cipher.final
    Base64.urlsafe_encode64(data)
  end

  # Traslate secure petitions
  def self.lang_key key
    file = File.read('../utils/key_lang.json')
    data_hash = JSON.parse(file)
    data_hash[key]
  end

end
