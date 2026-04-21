defmodule Trivium.EventsTest do
  use ExUnit.Case, async: true

  alias Trivium.Events

  describe "subscribe/publish/unsubscribe" do
    test "subscriber recebe evento publicado no próprio topic" do
      session_id = make_ref()
      Events.subscribe(session_id)

      Events.publish(session_id, :hello)

      assert_receive {:harness_event, :hello}
    end

    test "não recebe evento de outro topic" do
      my_session = make_ref()
      other_session = make_ref()
      Events.subscribe(my_session)

      Events.publish(other_session, :not_for_me)

      refute_receive {:harness_event, :not_for_me}, 100
    end

    test "múltiplos subscribers no mesmo topic recebem todos" do
      session_id = make_ref()
      parent = self()

      sub1 =
        spawn(fn ->
          Events.subscribe(session_id)
          send(parent, :sub1_ready)

          receive do
            {:harness_event, ev} -> send(parent, {:sub1_got, ev})
          end
        end)

      sub2 =
        spawn(fn ->
          Events.subscribe(session_id)
          send(parent, :sub2_ready)

          receive do
            {:harness_event, ev} -> send(parent, {:sub2_got, ev})
          end
        end)

      assert_receive :sub1_ready
      assert_receive :sub2_ready

      Events.publish(session_id, :broadcast)

      assert_receive {:sub1_got, :broadcast}
      assert_receive {:sub2_got, :broadcast}

      Process.exit(sub1, :kill)
      Process.exit(sub2, :kill)
    end

    test "após unsubscribe não recebe mais" do
      session_id = make_ref()
      Events.subscribe(session_id)
      Events.unsubscribe(session_id)

      Events.publish(session_id, :ignored)

      refute_receive {:harness_event, :ignored}, 100
    end

    test "publish sem subscribers não explode" do
      session_id = make_ref()
      assert Events.publish(session_id, :nobody_listening) == :ok
    end
  end
end
