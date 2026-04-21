defmodule Trivium.RendererTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Trivium.{Events, Renderer}
  alias Trivium.Types.Review

  describe "ciclo de vida start/stop" do
    test "start retorna pid e stop encerra o processo" do
      session_id = make_ref()
      pid = Renderer.start(session_id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      Renderer.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "rendering de eventos" do
    test ":session_started imprime cabeçalho" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, :session_started)
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "Starting evaluation"
    end

    test "{:attempt_started, n, total} imprime número da tentativa" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, {:attempt_started, 2, 3})
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "attempt 2/3"
    end

    test "{:agent_finished, role, :review, review} mostra score" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          review = %Review{role: :qa, score: 8, justification: "ok"}
          Events.publish(session_id, {:agent_finished, :qa, :review, review})
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "8/10"
    end

    test "{:scores_computed, _, :pass} mostra sucesso" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, {:scores_computed, [], :pass})
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "approved"
    end

    test "{:scores_computed, _, :fail} mostra falha/refino" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, {:scores_computed, [], :fail})
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "failed" or output =~ "refining"
    end

    test "eventos desconhecidos são ignorados sem crash" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, :evento_desconhecido)
          Events.publish(session_id, {:tuple_estranho, 1, 2, 3, 4})
          Process.sleep(50)
          assert Process.alive?(pid)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert is_binary(output)
    end

    test "{:agent_error, role, reason} imprime erro" do
      output =
        capture_io(fn ->
          session_id = make_ref()
          pid = Renderer.start(session_id)
          Events.publish(session_id, {:agent_error, :qa, :network_timeout})
          Process.sleep(50)
          Renderer.stop(pid)
          Process.sleep(50)
        end)

      assert output =~ "error"
    end
  end
end
