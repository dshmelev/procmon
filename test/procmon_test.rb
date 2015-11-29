require 'test_helper'

class ProcmonTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Procmon::VERSION
  end

  def test_app_class
    # Check autorun
    app = Procmon::App.new { true }
    assert !app.run?,
           "Should not be started."

    # Check start
    app.start
    assert app.run?,
           "Should be running"

    # Check restart
    pid = app.pid
    app.restart
    assert pid != app.pid,
          "Should be restarted"
    assert app.run?,
           "Should be running"

    # Check stop
    app.stop
    assert !app.run?,
           "Should not be started."

    # Check validator
    app = Procmon::App.new
    assert !app.valid?,
           "Should not be valid."
    app = Procmon::App.new { true }
    assert app.valid?,
           "Should be valid."
  end

  def test_observer_checker_class
    # Check validator
    observer = Procmon::Observer.new
    assert !observer.valid?,
           "Should not be valid."
    observer = Procmon::Observer.new(
      :apps     => [ Procmon::App.new { true }],
      :checkers => [ Procmon::CpuMon.new(:trigger => 80)])
    assert observer.valid?,
           "Should be valid."
  end

  def test_checkers
    checker = Procmon::CpuMon.new
    checker.stub :stat, { :cputime => 0 } do
      assert checker.get(0) == 0,
             "Should be 0"
    end
    checker.stub :stat, { :cputime => 25 } do
      assert checker.get(0) == 25,
             "Should be 25"
    end
    checker.stub :stat, { :cputime => 100 } do
      assert checker.get(0) == 75,
             "Should be 75"
    end
    checker.stub :stat, { :cputime => 100 } do
      assert checker.get(0) == 0,
             "Should be 0"
    end
  end

  def test_killing_app
    pid = rand(10000) # Generate PID
    checker_mock = MiniTest::Mock.new
    app_mock = MiniTest::Mock.new
    # mock expects:
    #                    method         return   arguments        comments
    #-------------------------------------------------------------
    app_mock.expect(     :instance_of?, true,    [Procmon::App])  # Validate Apps of Observer
    app_mock.expect(     :start,        true                   )  # Start App
    app_mock.expect(     :run?,         true                   )  # Check running App. Return true
    app_mock.expect(     :instance_of?, true,    [Procmon::App])  # Validate Apps of Observer
    app_mock.expect(     :pid,          pid                    )  # Get pid for checker
    checker_mock.expect( :get,          0,       [pid]         )  # Get value by PID. Expected to continue.
    checker_mock.expect( :trigger,      80                     )  # Compare with trigger
    app_mock.expect(     :run?,         true                   )  # Check running App. Return true
    app_mock.expect(     :instance_of?, true,    [Procmon::App])  # Validate Apps of Observer
    app_mock.expect(     :pid,          pid                    )  # Get pid for checker
    checker_mock.expect( :get,          100,     [pid]         )  # Get value by PID. Expected to restart.
    checker_mock.expect( :trigger,      80                     )  # Compare with trigger
    app_mock.expect(     :restart,      true                   )  # Restart App
    app_mock.expect(     :run?,         true                   )  # Check running App
    app_mock.expect(     :instance_of?, true,    [Procmon::App])  # Validate Apps of Observer
    app_mock.expect(     :pid,          pid                    )  # Get pid for checker
    checker_mock.expect( :get,          0,       [pid]         )  # Get value by PID. Expected to continue.
    checker_mock.expect( :trigger,      80                     )  # Compare with trigger
    app_mock.expect(     :run?,         false                  )  # Check running App
    app_mock.expect(     :pid,          pid                    )  # Get PID for exit message

    observer = Procmon::Observer.new(
        :apps     => [ app_mock ],
        :checkers => [ checker_mock ])
    observer.run

    assert app_mock.verify
  end

end
