defmodule ShortMaps do
  @default_modifier ?s

  @doc ~S"""
  Returns a map with the given keys bound to variables with the same name.

  This macro sigil is used to reduce boilerplate when writing pattern matches on
  maps that bind variables with the same name as the map keys. For example,
  given a map that looks like this:

      my_map = %{foo: "foo", bar: "bar", baz: "baz"}

  ..the following is very common Elixir code:

      %{foo: foo, bar: bar, baz: baz} = my_map
      foo #=> "foo"

  The `~m` sigil provides a shorter way to do exactly this. It splits the given
  list of words on whitespace (i.e., like the `~w` sigil) and creates a map with
  these keys as the keys and with variables with the same name as values. Using
  this sigil, this code can be reduced to just this:

      ~m(foo bar baz)a = my_map
      foo #=> "foo"

  `~m` can be used in regular pattern matches like the ones in the examples
  above but also inside function heads:

      defmodule Test do
        import ShortMaps

        def test(~m(foo)a), do: foo
        def test(_),       do: :no_match
      end

      Test.test %{foo: "hello world"} #=> "hello world"
      Test.test %{bar: "hey there!"}  #=> :no_match

  ## Modifiers

  The `~m` sigil supports both maps with atom keys as well as string keys. Atom
  keys can be specified using the `a` modifier, while string keys can be
  specified with the `s` modifier (which is the default).

      iex> ~m(my_key)s = %{"my_key" => "my value"}
      iex> my_key
      "my value"

      iex> ~m(my_key)a = %{my_key: "my value"}
      iex> my_key
      "my value"

  ## Pinning

  Matching using the `~m` sigil has full support for the pin operator:

      iex> bar = "bar"
      iex> ~m(foo ^bar)a = %{foo: "foo", bar: "bar"} #=> this is ok, `bar` matches
      iex> foo
      "foo"
      iex> bar
      "bar"
      iex> ~m(foo ^bar)a = %{foo: "FOO", bar: "bar"}
      iex> foo # still ok, since we didn't pin `foo`, it's now bound to a new value
      "FOO"
      iex> bar
      "bar"
      iex> ~m(^bar)a = %{foo: "foo", bar: "BAR"}
      ** (MatchError) no match of right hand side value: %{bar: "BAR", foo: "foo"}

  ## Structs

  For using structs instead of plain maps, the first word must be the struct
  name prefixed with `%`:

      defmodule Foo do
        defstruct bar: nil
      end

      ~m(%Foo bar)a = %Foo{bar: 4711}
      bar #=> 4711

  Structs only support atom keys, so you **must** use the `a` modifier or an
  exception will be raised.

  ## Pitfalls

  Interpolation isn't supported. `~m(#{foo})` will raise an `ArgumentError`
  exception.

  The variables associated with the keys in the map have to exist in the scope
  if the `~m` sigil is used outside a pattern match:

      foo = "foo"
      ~m(foo bar) #=> ** (RuntimeError) undefined function: bar/0

  ## Discussion

  For more information on this sigil and the discussion that lead to it, visit
  [this
  topic](https://groups.google.com/forum/#!topic/elixir-lang-core/NoUo2gqQR3I)
  in the Elixir mailing list.

  """
  defmacro sigil_m(term, modifiers)

  defmacro sigil_m({:<<>>, line, [string]}, modifiers) do
    sigil_m_function(line, String.split(string), modifier(modifiers), __CALLER__)
  end

  defmacro sigil_m({:<<>>, _, _}, _modifiers) do
    raise ArgumentError, "interpolation is not supported with the ~m sigil"
  end

  # We raise when the modifier is ?s and we're trying to build a struct.
  defp sigil_m_function(_line, ["%" <> _struct_name | _rest], ?s, _caller) do
    raise ArgumentError, "structs can only consist of atom keys"
  end

  defp sigil_m_function(_lin, ["%" <> struct_name | rest], ?a, caller) do
    struct_module_quoted = resolve_module(struct_name, caller)
    pairs = make_pairs(rest, ?a)
    quote do: %unquote(struct_module_quoted){unquote_splicing(pairs)}
  end

  defp sigil_m_function(line, words, modifier, _caller) do
    pairs = make_pairs(words, modifier)
    {:%{}, line, pairs}
  end

  defp resolve_module(struct_name, env) do
    Code.string_to_quoted!(struct_name, file: env.file, line: env.line)
  end

  defp make_pairs(words, modifier) do
    keys      = Enum.map(words, &strip_pin/1)
    variables = Enum.map(words, &handle_var/1)

    ensure_valid_variable_names(keys)

    case modifier do
      ?a -> keys |> Enum.map(&String.to_atom/1) |> Enum.zip(variables)
      ?s -> keys |> Enum.zip(variables)
    end
  end

  defp strip_pin("^" <> name),
    do: name
  defp strip_pin(name),
    do: name

  defp handle_var("^" <> name) do
    {:^, [], [Macro.var(String.to_atom(name), nil)]}
  end
  defp handle_var(name) do
    String.to_atom(name) |> Macro.var(nil)
  end

  defp modifier([]),
    do: @default_modifier
  defp modifier([mod]) when mod in 'as',
    do: mod
  defp modifier(_),
    do: raise(ArgumentError, "only these modifiers are supported: s, a")

  defp ensure_valid_variable_names(keys) do
    Enum.each keys, fn k ->
      unless k =~ ~r/\A[a-zA-Z_]\w*\Z/ do
        raise ArgumentError, "invalid variable name: #{k}"
      end
    end
  end
end
