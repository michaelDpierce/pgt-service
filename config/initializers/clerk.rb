require "clerk"

Clerk.configure do |c|
  c.secret_key = ENV["CLERK_SECRET_KEY"]
  c.publishable_key = ENV["CLERK_PUBLISHABLE_KEY"]
  c.logger = Logger.new(STDOUT)
  # c.excluded_routes = [ "/foo", "/bar/*" ]
end
