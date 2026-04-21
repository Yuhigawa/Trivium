defmodule Trivium.TypesTest do
  use ExUnit.Case, async: true

  alias Trivium.Types.{Attempt, Idea, Result, Review}

  describe "Idea" do
    test "cria struct com content" do
      idea = %Idea{content: "hello"}
      assert idea.content == "hello"
    end

    test "content é enforced" do
      assert_raise ArgumentError, fn ->
        struct!(Idea, [])
      end
    end
  end

  describe "Review" do
    test "cria struct com todos os campos obrigatórios" do
      r = %Review{role: :qa, score: 8, justification: "ok"}
      assert r.role == :qa
      assert r.score == 8
      assert r.justification == "ok"
    end

    test "enforça presença dos três campos" do
      assert_raise ArgumentError, fn -> struct!(Review, role: :qa) end
      assert_raise ArgumentError, fn -> struct!(Review, role: :qa, score: 5) end
    end
  end

  describe "Attempt" do
    test "cria struct com idea e reviews" do
      attempt = %Attempt{
        n: 1,
        idea: %Idea{content: "x"},
        reviews: [%Review{role: :qa, score: 8, justification: "j"}]
      }

      assert attempt.n == 1
      assert length(attempt.reviews) == 1
    end
  end

  describe "Result" do
    test "final_idea e final_reviews opcionais" do
      r = %Result{status: :error, attempts: []}
      assert r.final_idea == nil
      assert r.final_reviews == nil
    end

    test "status e attempts obrigatórios" do
      assert_raise ArgumentError, fn -> struct!(Result, []) end
      assert_raise ArgumentError, fn -> struct!(Result, status: :approved) end
    end
  end
end
