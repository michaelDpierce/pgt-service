Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins  "http://localhost:3001", ENV.fetch("FRONTEND_ORIGIN", "*")
    resource "*",
      headers: :any,
      expose: [ "Authorization" ],
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ]
  end
end
