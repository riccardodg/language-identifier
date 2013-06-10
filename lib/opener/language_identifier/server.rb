require 'sinatra/base'
require 'httpclient'

module Opener
  class LanguageIdentifier
    ##
    # A basic language identification server powered by Sinatra.
    #
    class Server < Sinatra::Base
      configure do
        enable :logging
      end

      configure :development do
        set :raise_errors, true
        set :dump_errors, true
      end

      ##
      # Provides a page where you see a textfield and you can post stuff
      #
      get '/' do
        erb :index
      end

      ##
      # Identifies a given text.
      #
      # @param [Hash] params The POST parameters.
      #
      # @option params [String] :text The text to identify.
      # @option params [TrueClass|FalseClass] :kaf Whether or not to use KAF
      #  output.
      # @option params [TrueClass|FalseClass] :extended Whether or not to use
      #  extended language detection.
      # @option params [Array<String>] :callbacks A collection of callback URLs
      #  that act as a chain. The results are posted to the first URL which is
      #  then shifted of the list.
      # @option params [String] :error_callback Callback URL to send errors to
      #  when using the asynchronous setup.
      #
      post '/' do
        if !params[:text] or params[:text].strip.empty?
          logger.error('Failed to process the request: no text specified')

          halt(400, 'No text specified')
        end

        params[:callbacks] ? process_async : process_sync
      end

      private

      ##
      # Processes the request synchronously.
      #
      def process_sync
        output = identify_text(params[:text])

        body(output)
      rescue => error
        logger.error("Failed to identify the text: #{error.inspect}")

        halt(500, error.message)
      end

      ##
      # Processes the request asynchronously.
      #
      def process_async
        callbacks = params[:callbacks]
        callbacks = [callbacks] unless callbacks.is_a?(Array)

        Thread.new do
          identify_async(params[:text], callbacks, params[:error_callback])
        end

        status(202)
      end

      ##
      # @param [String] text The text to identify.
      # @return [String]
      # @raise RuntimeError Raised when the language identification process
      #  failed.
      #
      def identify_text(text)
        identifier            = LanguageIdentifier.new(options_from_params)
        output, error, status = identifier.run(text)

        raise(error) unless status.success?

        return output
      end

      ##
      # Returns a Hash containing various GET/POST parameters extracted from
      # the `params` Hash.
      #
      # @return [Hash]
      #
      def options_from_params
        options = {}

        [:kaf, :extended, :callback].each do |key|
          options[key] = params[key]
        end

        return options
      end

      ##
      # Identifies the text and submits it to a callback URL.
      #
      # @param [String] text
      # @param [Array] callbacks
      # @param [String] error_callback
      #
      def identify_async(text, callbacks, error_callback = nil)
        begin
          language = identify_text(text)
        rescue => error
          logger.error("Failed to identify the text: #{error.message}")

          submit_error(error_callback, error.message) if error_callback
        end

        url = callbacks.shift

        logger.info("Submitting results to #{url}")

        begin
          process_callback(url, language, callbacks)
        rescue => error
          logger.error("Failed to submit the results: #{error.inspect}")

          submit_error(error_callback, error.message) if error_callback
        end
      end

      ##
      # @param [String] url
      # @param [String] language
      # @param [Array] callbacks
      #
      def process_callback(url, language, callbacks)
        HTTPClient.post(
          url,
          :body => {:language => language, :callbacks => callbacks}
        )
      end

      ##
      # @param [String] url
      # @param [String] message
      #
      def submit_error(url, message)
        HTTPClient.post(url, :body => {:error => message})
      end
    end # Server
  end # LanguageIdentifier
end # Opener
