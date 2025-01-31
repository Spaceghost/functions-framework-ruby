# Copyright 2020 Google LLC
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

require "helper"
require "ostruct"

describe FunctionsFramework::Function do
  it "represents an http function using a block" do
    tester = self
    function = FunctionsFramework::Function.http "my_func" do |request|
      tester.assert_equal "the-request", request
      tester.assert_equal "my_func", global(:function_name)
      "hello"
    end
    assert_equal "my_func", function.name
    assert_equal :http, function.type
    response = function.call "the-request", globals: { function_name: function.name }
    assert_equal "hello", response
  end

  it "represents an http function using a block with a return statement" do
    function = FunctionsFramework::Function.http "my_func" do |request|
      return "hello" if request == "the-request"
      "goodbye"
    end
    assert_equal "my_func", function.name
    assert_equal :http, function.type
    response = function.call "the-request"
    assert_equal "hello", response
  end

  it "defines a cloud_event function using a block" do
    tester = self
    function = FunctionsFramework::Function.cloud_event "my_event_func" do |event|
      tester.assert_equal "the-event", event
      tester.assert_equal "my_event_func", global(:function_name)
      "ok"
    end
    assert_equal "my_event_func", function.name
    assert_equal :cloud_event, function.type
    function.call "the-event", globals: { function_name: function.name }
  end

  it "defines a startup function using a block" do
    tester = self
    function = FunctionsFramework::Function.startup_task do |func|
      tester.assert_equal "the-function", func
      tester.assert_nil global(:function_name)
    end
    assert_nil function.name
    assert_equal :startup_task, function.type
    function.call "the-function", globals: { function_name: function.name }
  end

  it "represents an http function using an object" do
    callable = proc do |request|
      request
    end
    function = FunctionsFramework::Function.http "my_func", callable: callable
    assert_equal "my_func", function.name
    assert_equal :http, function.type
    response = function.call "the-request"
    assert_equal "the-request", response
  end

  it "represents an http function using a class" do
    class MyCallable
      def initialize **_keywords
      end

      def call request
        request == "the-request" ? "hello" : "whoops"
      end
    end

    function = FunctionsFramework::Function.http "my_func", callable: MyCallable
    assert_equal "my_func", function.name
    assert_equal :http, function.type
    response = function.call "the-request"
    assert_equal "hello", response
  end

  it "can call a startup function with no formal argument" do
    tester = self
    function = FunctionsFramework::Function.startup_task do
      tester.assert_nil global(:function_name)
    end
    function.call "the-function", globals: { function_name: function.name }
  end

  it "sets a global from a startup task" do
    tester = self
    startup = FunctionsFramework::Function.startup_task do
      set_global :foo, :bar
    end
    function = FunctionsFramework::Function.http "my_func" do |_request|
      tester.assert_equal :bar, global(:foo)
      "hello"
    end
    globals = {}
    startup.call "the-startup", globals: globals
    function.call "the-function", globals: globals
  end

  it "sets a lazy global from a startup task" do
    tester = self
    counter = 0
    startup = FunctionsFramework::Function.startup_task do
      set_global :foo do
        counter += 1
        :bar
      end
    end
    function = FunctionsFramework::Function.http "my_func" do |_request|
      tester.assert_equal :bar, global(:foo)
      "hello"
    end
    globals = {}
    startup.call "the-startup", globals: globals
    assert_equal 0, counter
    function.call "the-function", globals: globals
    assert_equal 1, counter
    function.call "the-function", globals: globals
    assert_equal 1, counter
  end

  it "allows a global of type Minitest::Mock" do
    startup = FunctionsFramework::Function.startup_task do
      set_global :foo, Minitest::Mock.new
    end
    function = FunctionsFramework::Function.http "my_func" do |_request|
      global :foo
      "hello"
    end
    globals = {}
    startup.call "the-startup", globals: globals
    function.call "the-function", globals: globals
  end

  describe "typed" do
    # Ruby class representing a single integer value encoded as a JSON int
    class IntValue
      def initialize val
        @value = val
      end

      def self.decode_json json
        IntValue.new json.to_i
      end

      def to_json(*_args)
        get.to_s
      end

      def get
        @value
      end
    end

    # class_func provides a function as a class that implements the Callable
    # interface.
    class_func = ::Class.new FunctionsFramework::Function::Callable do
      define_method :call do |_request|
        global :function_name
      end
    end

    it "can be defined with no custom type" do
      function = FunctionsFramework::Function.typed "int_adder" do |request|
        request + 1
      end
      assert_equal "int_adder", function.name
      assert_equal :typed, function.type

      res = function.call 1, globals: {}

      assert_equal 2, res
    end

    it "can be defined using a block and custom_type" do
      function = FunctionsFramework::Function.typed "int_adder", request_class: IntValue do |request|
        IntValue.new request.get + 1
      end
      assert_equal "int_adder", function.name
      assert_equal :typed, function.type

      res = function.call IntValue.new(1), globals: {}

      assert_equal 2, res.get
    end

    it "can be defined using a callable class" do
      function = FunctionsFramework::Function.typed "using_callable_class", callable: class_func
      assert_equal "using_callable_class", function.name
      assert_equal :typed, function.type
      globals = function.populate_globals

      res = function.call nil, globals: globals

      assert_equal function.name, res
    end

    it "can be defined using an instance of a callable" do
      callable_class = class_func.new globals: { function_name: "fake_global_name" }
      function = FunctionsFramework::Function.typed "using_callable", callable: callable_class
      assert_equal "using_callable", function.name
      assert_equal :typed, function.type
      globals = function.populate_globals

      res = function.call nil, globals: globals

      assert_equal "fake_global_name", res
    end

    it "function can access globals" do
      function = FunctionsFramework::Function.typed "printName" do |_request|
        global :function_name
      end
      globals = function.populate_globals

      res = function.call nil, globals: globals

      assert_equal function.name, res
    end

    it "function rejects request_class that does not implement decode_json" do
      assert_raises ::ArgumentError do
        FunctionsFramework::Function.typed "bad_fn", request_class: ::Class
      end
    end

    it "function includes a module in a function's singleton class during definition" do
      mod = Module.new do
        def block_included_method
          "included method response"
        end
      end

      function = FunctionsFramework::Function.http "my_func" do
        include mod
        "original response"
      end
      response = function.call "the-request", globals: { function_name: function.name }

      assert function.callable_class.included_modules.include?(mod)
      assert_equal "original response", response
    end

    it "function includes a module in a function's singleton class after definition" do
      mod = Module.new do
        def included_method
          "included method response"
        end
      end
      function = FunctionsFramework::Function.http "my_func" do
        "original response"
      end
      function.include mod

      assert function.callable_class.included_modules.include? mod
      response = function.call "the-request", globals: { function_name: function.name }
      assert_equal "original response", response
    end

    it "function retains function behavior when including multiple modules" do
      mod1 = Module.new do
        def call(*)
          "#{method_from_mod1} call"
        end

        def method_from_mod1
          "response from mod1"
        end
      end

      mod2 = Module.new do
        def method_from_mod2
          "response from mod2"
        end

        def call(*)
          super
        end
      end

      mod3 = Module.new do
        def method_from_mod3
          "response from mod3"
        end
      end

      function = FunctionsFramework::Function.http "my_func" do
        include mod1
        include mod2

        super()
      end
      function.include mod3
      refute function.callable_class.included_modules.include? mod1
      refute function.callable_class.included_modules.include? mod2
      assert function.callable_class.included_modules.include? mod3
      response = function.call "the-request", globals: { function_name: function.name }

      assert function.callable_class.included_modules.include? mod1
      assert function.callable_class.included_modules.include? mod2
      assert function.callable_class.included_modules.include? mod3
      assert_equal "response from mod1 call", response
    end

    it "handles including modules by function name during and after definition" do
      mod1 = Module.new do
        def included_method
          "included method response"
        end
      end

      mod2 = Module.new do
        def block_included_method
          "block included method response"
        end
      end

      function = FunctionsFramework::Function.http "my_func" do
        include mod2
        "original response"
      end
      function.include mod1
      assert function.callable_class.included_modules.include? mod1
      refute function.callable_class.included_modules.include? mod2

      response = function.call "the-request"
      assert function.callable_class.included_modules.include? mod1
      assert function.callable_class.included_modules.include? mod2
      assert_equal "original response", response
    end

    it "handles including modules using a callable class but does not share included modules across functions" do
      klass = Class.new do
        def initialize **_keywords
        end

        def call request
          request == "the-request" ? "hello" : "whoops"
        end
      end

      mod1 = Module.new do
        def included_method
          "included method response"
        end
      end

      function = FunctionsFramework::Function.http "my_func", callable: klass
      function.include mod1
      assert function.callable_class.included_modules.include?(mod1)

      assert_equal "my_func", function.name
      assert_equal :http, function.type
      response = function.call "the-request"
      assert_equal "hello", response

      function2 = FunctionsFramework::Function.http "my_func2", callable: klass
      function2.call "the-request"
      refute function2.callable_class.included_modules.include?(mod1)
    end

    it "handles including modules using a callable object but does not share included modules across functions" do
      mod1 = Module.new do
        def included_method
          "included method response"
        end
      end
      object = lambda do |_request|
        include mod1

        included_method
      end
      mod2 = Module.new do
        def included_method2
          "included method2 response"
        end
      end
      object3 = Object.new.tap do |obj|
        obj.singleton_class.define_method :call do |_request = nil|
          include mod1

          [included_method, included_method2].join " and "
        end
      end

      function = FunctionsFramework::Function.http "my_func", callable: object
      refute function.callable_class.included_modules.include? mod1
      function.include mod2
      assert function.callable_class.included_modules.include? mod2

      response = function.call "the-request"

      assert function.callable_class.included_modules.include? mod1
      assert function.callable_class.included_modules.include? mod2
      assert_equal "included method response", response

      function2 = FunctionsFramework::Function.http "my_func2", callable: object
      refute function2.callable_class.included_modules.include? mod1
      function2.call "the-request"
      assert function2.callable_class.included_modules.include? mod1
      refute function2.callable_class.included_modules.include? mod2

      function3 = FunctionsFramework::Function.http "my_func3", callable: object3
      refute function3.callable_class.included_modules.include? mod1
      refute function3.callable_class.included_modules.include? mod2

      function3.include mod2
      response = function3.call "the-request"
      assert function3.callable_class.included_modules.include? mod1
      assert function3.callable_class.included_modules.include? mod2

      assert_equal "included method response and included method2 response", response
    end
  end
end
