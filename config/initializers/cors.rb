Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'https://superappproject.com', 
            'https://www.superappproject.com', 
            'http://localhost:3000',
            /https:\/\/.+\.superappproject\.com/

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true,
      expose: ['X-CSRF-Token', 'X-Set-Storage', 'access-token', 'expiry', 'token-type', 'uid', 'client']
  end
end
