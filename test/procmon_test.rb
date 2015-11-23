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

  def test_observer_class
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

end
