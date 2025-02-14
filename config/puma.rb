environment ENV.fetch("RAILS_ENV") { "production" }
port 3000
bind "tcp://0.0.0.0:3000"
threads 1, 5
workers 2
preload_app!

if ENV['RAILS_ENV'] == 'production'
  ssl_bind '0.0.0.0', '443', {
    key: '/etc/letsencrypt/live/superappproject.com/privkey.pem',
    cert: '/etc/letsencrypt/live/superappproject.com/fullchain.pem',
    verify_mode: 'none'
  }
end
