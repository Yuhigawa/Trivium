defmodule Trivium.Build.DiffFilterTest do
  use ExUnit.Case, async: true

  alias Trivium.Build.DiffFilter

  test "passes through an empty diff unchanged" do
    assert DiffFilter.filter("") == ""
  end

  test "keeps source-code diffs untouched" do
    diff = """
    diff --git a/lib/foo.ex b/lib/foo.ex
    index 1234..5678 100644
    --- a/lib/foo.ex
    +++ b/lib/foo.ex
    @@ -1,3 +1,3 @@
     defmodule Foo do
    -  def bar, do: 1
    +  def bar, do: 2
     end
    """

    assert DiffFilter.filter(diff) == diff
  end

  test "drops mix.lock changes" do
    diff = """
    diff --git a/mix.lock b/mix.lock
    index aaa..bbb 100644
    --- a/mix.lock
    +++ b/mix.lock
    @@ -1 +1 @@
    -%{"jason": ...}
    +%{"jason": ...new...}
    """

    assert DiffFilter.filter(diff) == ""
  end

  test "drops binary file diffs" do
    diff = """
    diff --git a/trivium b/trivium
    index aaa..bbb 100755
    Binary files a/trivium and b/trivium differ
    """

    assert DiffFilter.filter(diff) == ""
  end

  test "drops vendored deps and build artefacts" do
    diff = """
    diff --git a/deps/jason/lib/jason.ex b/deps/jason/lib/jason.ex
    --- a/deps/jason/lib/jason.ex
    +++ b/deps/jason/lib/jason.ex
    @@ -1 +1 @@
    -old
    +new
    diff --git a/_build/dev/lib/foo.beam b/_build/dev/lib/foo.beam
    Binary files a/_build/dev/lib/foo.beam and b/_build/dev/lib/foo.beam differ
    diff --git a/node_modules/react/index.js b/node_modules/react/index.js
    --- a/node_modules/react/index.js
    +++ b/node_modules/react/index.js
    @@ -1 +1 @@
    -a
    +b
    """

    assert DiffFilter.filter(diff) == ""
  end

  test "keeps source diffs and drops noise in the same diff" do
    diff = """
    diff --git a/lib/keep.ex b/lib/keep.ex
    --- a/lib/keep.ex
    +++ b/lib/keep.ex
    @@ -1 +1 @@
    -a
    +b
    diff --git a/mix.lock b/mix.lock
    --- a/mix.lock
    +++ b/mix.lock
    @@ -1 +1 @@
    -x
    +y
    diff --git a/lib/also_keep.ex b/lib/also_keep.ex
    --- a/lib/also_keep.ex
    +++ b/lib/also_keep.ex
    @@ -1 +1 @@
    -c
    +d
    """

    out = DiffFilter.filter(diff)
    assert String.contains?(out, "lib/keep.ex")
    assert String.contains?(out, "lib/also_keep.ex")
    refute String.contains?(out, "mix.lock")
  end

  test "does not match a file just because its path contains a drop substring" do
    diff = """
    diff --git a/lib/my_node_modules_helper.ex b/lib/my_node_modules_helper.ex
    --- a/lib/my_node_modules_helper.ex
    +++ b/lib/my_node_modules_helper.ex
    @@ -1 +1 @@
    -a
    +b
    """

    assert DiffFilter.filter(diff) == diff
  end
end
