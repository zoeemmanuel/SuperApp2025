require_relative "boot"
require "rails/all"
require 'dotenv/load' if Rails.env.development?

Bundler.require(*Rails.groups)

module SuperappPoc1
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Cookie configurations for cross-browser support
    config.action_dispatch.cookies_same_site_protection = lambda { |_request|
      { same_site: :none }
    }
    config.action_dispatch.cookies_serializer = :json
    config.action_dispatch.use_cookies_with_metadata = true

    config.action_dispatch.cookies_rotations.tap do |cookies|
      cookies.rotate :signed
      cookies.rotate :encrypted
    end

    config.action_dispatch.default_headers = {
      'X-Frame-Options' => 'SAMEORIGIN',
      'X-XSS-Protection' => '1; mode=block',
      'X-Content-Type-Options' => 'nosniff',
      'X-Download-Options' => 'noopen',
      'X-Permitted-Cross-Domain-Policies' => 'none'
    }

    config.hosts << '.superappproject.com'
    config.hosts << 'superappproject.com'
    config.hosts << '167.99.89.187'

    config.autoload_lib(ignore: %w(assets tasks))
  end
end
