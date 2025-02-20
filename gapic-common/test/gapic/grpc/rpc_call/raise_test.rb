# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "test_helper"
require "gapic/grpc"

class RpcCallRaiseTest < Minitest::Test
  def test_traps_exception
    api_meth_stub = proc do |*_args|
      raise GRPC::Unknown
    end

    rpc_call = Gapic::ServiceStub::RpcCall.new api_meth_stub

    assert_raises GRPC::BadStatus do
      rpc_call.call Object.new
    end
  end

  def test_traps_wrapped_exception
    api_meth_stub = proc do
      raise FakeCodeError.new("Not a real GRPC error",
                              GRPC::Core::StatusCodes::UNAVAILABLE)
    end

    rpc_call = Gapic::ServiceStub::RpcCall.new api_meth_stub

    assert_raises FakeCodeError do
      rpc_call.call Object.new
    end
  end

  def test_wraps_grpc_errors
    deadline_arg = nil
    call_count = 0

    api_meth_stub = proc do |deadline: nil, **_kwargs|
      deadline_arg = deadline
      call_count += 1
      raise GRPC::BadStatus.new(2, "unknown")
    end

    rpc_call = Gapic::ServiceStub::RpcCall.new api_meth_stub

    assert_raises GRPC::BadStatus do
      rpc_call.call Object.new, options: { timeout: 300 }
    end

    assert_kind_of Time, deadline_arg
    assert_equal 1, call_count
  end

  def test_wont_wrap_non_grpc_errors
    deadline_arg = nil
    call_count = 0

    api_meth_stub = proc do |deadline: nil, **_kwargs|
      deadline_arg = deadline
      call_count += 1
      raise FakeCodeError.new("Not a real GRPC error",
                              GRPC::Core::StatusCodes::UNAVAILABLE)
    end

    rpc_call = Gapic::ServiceStub::RpcCall.new api_meth_stub

    assert_raises FakeCodeError do
      rpc_call.call Object.new, options: { timeout: 300 }
    end
    assert_kind_of Time, deadline_arg
    assert_equal 1, call_count
  end

  ##
  # Tests that if a layer underlying the RpcCall throws a ::GRPC::Unavailable
  # that contains a Signet::AuthorizationError in its text,
  # it gets extracted and rewrapped into a G
  def test_will_rewrap_signet_errors
    signet_error_text = <<-SIGNET
    <Signet::AuthorizationError: Authorization failed.  Server message:
    {
       "error": "invalid_grant",
       "error_description": "Bad Request"
    }>
    SIGNET

    unauth_error_text = "#{::GRPC::Core::StatusCodes::UNAUTHENTICATED}:#{signet_error_text}"

    api_meth_stub = proc do |*_args|
      raise GRPC::Unavailable.new(signet_error_text)
    end

    rpc_call = Gapic::ServiceStub::RpcCall.new api_meth_stub

    ex = assert_raises Gapic::GRPC::AuthorizationError do
      rpc_call.call Object.new
    end

    assert_equal ::GRPC::Core::StatusCodes::UNAUTHENTICATED, ex.code
    assert_equal unauth_error_text, ex.message
    refute_nil ex.cause
    assert_kind_of GRPC::Unavailable, ex.cause
  end
end
