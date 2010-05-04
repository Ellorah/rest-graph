
require 'rest_client'

require 'cgi'

class RestGraph < Struct.new(:access_token, :graph_server, :fql_server,
                             :accept, :lang, :auto_decode, :app_id, :secret)
  def initialize o = {}
    self.access_token = o[:access_token]
    self.graph_server = o[:graph_server] || 'https://graph.facebook.com/'
    self.fql_server   = o[:fql_server]   || 'https://api.facebook.com/'
    self.accept       = o[:accept] || 'text/javascript'
    self.lang         = o[:lang]   || 'en-us'
    self.auto_decode  = o.key?(:auto_decode) ? o[:auto_decode] : true
    self.app_id       = o[:app_id]
    self.secret       = o[:secret]

    check_arguments!
  end

  def get    path, opts = {}
    request(graph_server, path, opts, :get)
  end

  def delete path, opts = {}
    request(graph_server, path, opts, :delete)
  end

  def post   path, payload, opts = {}
    request(graph_server, path, opts, :post, payload)
  end

  def put    path, payload, opts = {}
    request(graph_server, path, opts, :put,  payload)
  end

  def fql query, opts = {}
    request(fql_server, 'method/fql.query',
      {:query  => query, :format => 'json'}.merge(opts), :get)
  end

  # cookies, app_id, secrect related below

  def parse_token_in_rack_env! env
    self.access_token = env['HTTP_COOKIE'] =~ /fbs_#{app_id}="(.+?)"/ &&
      extract_token_if_sig_ok(Rack::Utils.parse_query($1))
  end

  def parse_token_in_cookies! cookies
    self.access_token = parse_token_in_fbs!(cookies["fbs_#{app_id}"])
  end

  def parse_token_in_fbs! fbs
    self.access_token = fbs &&
      extract_token_if_sig_ok(Rack::Utils.parse_query(fbs[1..-2]))
  end

  private
  def check_arguments!
    if auto_decode
      begin
        require 'json'
      rescue LoadError
        require 'json_pure'
      end
    end

    if app_id && secret # want to parse access_token in cookies
      require 'digest/md5'
      require 'rack'
    elsif app_id || secret
      raise ArgumentError.new("You may want to pass both"      \
                              " app_id(#{app_id.inspect}) and" \
                              " secret(#{secret.inspect})")
    end
  end

  def request server, path, opts, method, payload = nil
    post_request(
      RestClient::Resource.new(server)[path + build_query_string(opts)].
      send(method, *[payload, build_headers].compact))
  rescue RestClient::InternalServerError => e
    post_request(e.http_body)
  end

  def build_query_string q = {}
    query = q.merge(access_token ? {:access_token => access_token} : {})
    return '' if query.empty?
    return '?' + query.map{ |(k, v)| "#{k}=#{CGI.escape(v)}" }.join('&')
  end

  def build_headers
    headers = {}
    headers['Accept']          = accept if accept
    headers['Accept-Language'] = lang   if lang
    headers
  end

  def post_request result
    auto_decode ? JSON.parse(result) : result
  end

  def extract_token_if_sig_ok cookies
    cookies['access_token'] if calculate_sig(cookies) == cookies['sig']
  end

  def calculate_sig cookies
    args = cookies.reject{ |(k, v)| k == 'sig' }.sort.
      map{ |a| a.join('=') }.join

    Digest::MD5.hexdigest(args + secret)
  end
end
