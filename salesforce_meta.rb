require 'net/https'
require 'uri'
require 'zlib'
require 'stringio'

require 'rubygems'

gem 'builder', '>= 2.0.0'
require 'builder'

gem 'facets', '>= 2.4'
require 'facets/openhash'

require 'rforce/soap_response_rexml'
begin; require 'rforce/soap_response_hpricot'; rescue LoadError; end
begin; require 'rforce/soap_response_expat'; rescue LoadError; end

class SalesforceMeta
  # Use the fastest XML parser available.
  def self.parser(name)
      RForce.const_get(name) rescue nil
  end
  
  SoapResponse = 
    parser(:SoapResponseExpat) ||
    parser(:SoapResponseHpricot) ||
    SoapResponseRexml
  
  Envelope = <<-HERE
<?xml version="1.0" encoding="utf-8" ?>
<soapenv:Envelope
   xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
   xmlns:xsd="http://www.w3.org/2001/XMLSchema"
   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <soapenv:Header>
     <ns1:SessionHeader soapenv:mustUnderstand="0" xsi:type="ns1:SessionHeader"
         xmlns:ns1="http://soap.sforce.com/2006/04/metadata">
        <ns1:sessionId>%s</ns1:sessionId>
     </ns1:SessionHeader>
     <ns2:CallOptions soapenv:mustUnderstand="0" xsi:type="ns2:SessionHeader"
         xmlns:ns2="http://soap.sforce.com/2006/04/metadata">
        <ns2:client>apex_eclipse/16.0.200906151227</ns2:client>
     </ns2:CallOptions>
     <ns3:DebuggingHeader soapenv:mustUnderstand="0" xsi:type="ns3:DebuggingHeader"
         xmlns:ns3="http://soap.sforce.com/2006/04/metadata">
        <ns3:debugLevel xsi:nil="true" />
     </ns3:DebuggingHeader>
  </soapenv:Header>
  <soapenv:Body>
    %s
  </soapenv:Body>
</soapenv:Envelope>  
  HERE
  
  def create(opts)
    # Create XML text from the arguments.
    expanded = ''
    @builder = Builder::XmlMarkup.new(:target => expanded)
    @builder.tag! :create, :xmlns => "http://soap.sforce.com/2006/04/metadata" do |b|
      b.tag! :metadata, "xsi:type" => "ns2:CustomField", "xmlns:ns2" => "http://soap.sforce.com/2006/04/metadata" do |c|
        opts.each { |k,v| c.tag! k, v }
      end
    end
    call_remote(expanded)
  end
  
  def destroy(opts)
    expanded = ''
    @builder = Builder::XmlMarkup.new(:target => expanded)
    @builder.tag! :delete, :xmlns => "http://soap.sforce.com/2006/04/metadata" do |b|
      b.tag! :metadata, "xsi:type" => "ns2:CustomField", "xmlns:ns2" => "http://soap.sforce.com/2006/04/metadata" do |c|
        opts.each { |k,v| c.tag! k, v }
      end
    end
    call_remote(expanded)
  end
  
  def initialize
    salesforce = ApplicationController.salesforce
    @session_id = salesforce.session_id
    init_server( @session_id, ApplicationController.salesforce_metadata_server_url )
  end
  
  def init_server(session_id, url)
    @url = URI.parse(url)
    @server = Net::HTTP.new(@url.host, @url.port)
    @server.use_ssl = @url.scheme == 'https'
    @server.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
  
  # Call a method on the remote server.  Arguments can be
  # a hash or (if order is important) an array of alternating
  # keys and values.
  def call_remote(expanded)
    # Fill in the blanks of the SOAP envelope with our
    # session ID and the expanded XML of our request.
    request = (Envelope % [@session_id, expanded])
    
    puts expanded.inspect
    # gzip request
    request = encode(request)

    headers = {
      'Connection' => 'Keep-Alive',
      'Content-Type' => 'text/xml',
      'SOAPAction' => '""',
      'User-Agent' => 'activesalesforce rforce/1.0'
    }

    headers['Accept-Encoding'] = 'gzip'
    headers['Content-Encoding'] = 'gzip'

    # Send the request to the server and read the response.
    response = @server.post2(@url.path, request.lstrip, headers)

    # decode if we have encoding
    content = decode(response)

    SoapResponse.new(content).parse
  end
  
  # decode gzip
  def decode(response)
    encoding = response['Content-Encoding']

    # return body if no encoding
    if !encoding then return response.body end

    # decode gzip
    case encoding.strip
    when 'gzip' then
      begin
        gzr = Zlib::GzipReader.new(StringIO.new(response.body))
        decoded = gzr.read
      ensure
        gzr.close
      end
      decoded
    else
      response.body
    end
  end

  # encode gzip
  def encode(request)
    begin
      ostream = StringIO.new
      gzw = Zlib::GzipWriter.new(ostream)
      gzw.write(request)
      ostream.string
    ensure
      gzw.close
    end
  end
  
end

# extend Rforce

module RForce
  class Binding
    def session_id
      @session_id
    end
  end
end
