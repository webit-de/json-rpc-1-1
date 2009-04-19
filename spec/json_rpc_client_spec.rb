require File.dirname(__FILE__) + '/spec_helper'

describe JsonRpcClient do
  
  before :all do
    class FuBarController < ApplicationController
      json_rpc_service :name => 'TestService', :id => 'skdjfhsdhfkjshdjkhskdhfkjshdf'
      json_rpc_procedure :name => 'add', :params => [{:name => 'x', :type => 'any'}, 
                                                     {:name => 'y', :type => 'any'}], 
                         :proc => :+, :idempotent => true
      json_rpc_procedure :name => 'sub', :params => [{:name => 'x', :type => 'any'}, 
                                                     {:name => 'y', :type => 'any'}], 
                         :proc => :-, :idempotent => true
    end
        
    class FuBar < JsonRpcClient
      json_rpc_service 'http://localhost:8888/da_service', :no_auto_config => true, :retries => 2
    end
        
  end
  
  
  it "should request the system description when first called" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_return(stringify_symbols_in_hash(FuBarController.service.system_describe))
    FuBar.system_describe.should == {"procs"=>[{"name"=>"sub", "idempotent"=>true, "params"=>[{"name"=>"x", "type"=>"any"}, {"name"=>"y", "type"=>"any"}], "return"=>{"type"=>"any"}}, 
                                               {"name"=>"add", "idempotent"=>true, "params"=>[{"name"=>"x", "type"=>"any"}, {"name"=>"y", "type"=>"any"}], "return"=>{"type"=>"any"}}
                                              ], 
                                     "name"=>"TestService", 
                                     "id"=>"skdjfhsdhfkjshdjkhskdhfkjshdf", 
                                     "sdversion"=>"1.0"
                                    }
  end
  
  
  it "should raise a JsonRpcClient::ServiceError locally when the remote service returns an error" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '{"error": {"code": 123, "message": "Disaster!"}}',
                                                                     :content_type => 'application/json')))
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::ServiceError, 'JSON-RPC error 123 (localhost:8888): Disaster!')
  end
  
  
  it "should raise a JsonRpcClient::ServiceDown error when the client cannot reach the remote service" do
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::ServiceDown)
  end
  
  
  it "should raise a JsonRpcClient::NotAService when the service returns non-JSON data" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest,
                                                                     :code => 12345, :message => 'blablabla',
                                                                     :body => '{"error": {"code": 123, "message": "Disaster!"}}',
                                                                     :content_type => 'text/html')))
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::NotAService)
  end
  
  
  it "should raise a JsonRpcClient::GatewayTimeout when the service returns non-JSON data with a status code of 504" do
    Net::HTTP.should_receive(:start).exactly(3).times.with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest,
                                                                     :code => 504, :message => 'blablabla',
                                                                     :body => '{"error": {"code": 504, "message": "Disaster!"}}',
                                                                     :content_type => 'text/html')))
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::GatewayTimeout)
  end
  
  
  it "should raise a JsonRpcClient::ServiceUnavailable when the service returns non-JSON data with a status code of 503" do
    Net::HTTP.should_receive(:start).exactly(3).times.with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest,
                                                                     :code => 503, :message => 'blablabla',
                                                                     :body => '{"error": {"code": 503, "message": "Disaster!"}}',
                                                                     :content_type => 'text/html')))
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::ServiceUnavailable)
  end
  
  
  it "should raise a JsonRpcClient::ServiceReturnsJunk when the service returns unparseable JSON" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '<this>is not<json />but some sort of</markup>',
                                                                     :content_type => 'application/json')))
    lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::ServiceReturnsJunk)
  end
  
  
  # it "should translate ::Timeout::Error exceptions to JsonRpcClient::ServerTimeout exceptions" do
  #   Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).and_raise(::Timeout::Error)
  #   lambda { FuBar.add 1, 2 }.should raise_error(JsonRpcClient::ServerTimeout)
  # end
  
  
  it "should be possible to wrap a call in a retry_strategy block" do
    Net::HTTP.should_receive(:start).with("localhost", 8888, nil, nil).
              and_yield(mock_model(Net::HTTP, :request => mock_model(Net::HTTPRequest, 
                                                                     :body => '{"result": 30}',
                                                                     :content_type => 'application/json')))
    FuBar.retry_strategy(nil) do
      FuBar.add(10, 20)
    end
  end
    
end
