-module(tend_loader).

-export([load_url/3,
         guess_root/1
        ]).

-include_lib("ex_uri/include/ex_uri.hrl").

-define(REL_ATTR, <<"erlang-tend">>).

%% -----------------------------------------------------------------------------
%% API
%% -----------------------------------------------------------------------------
load_url(Url, Srcdir, Libdir) ->
    {ok, Response} = httpc:request(Url),
    {{_Vsn, 200, "OK"},
     Headers,
     Body} = Response,
    {"content-type", Content_type} = remove_encoding(
                                       proplists:lookup("content-type",
                                                        Headers)),
    dispatch(Url, Content_type, Body, Srcdir, Libdir).

guess_root(Dirs) ->
    %% We guess that based on the common Erlang repo, the root
    %% of the application is the level above 'src/' or 'ebin/'
    Fragments = [filename:split(X) || X <- Dirs],
    MakeDir = fragments_to_base(Fragments, "Makefile"),
    RebarDir = fragments_to_base(Fragments, "rebar"),
    EmakeDir = fragments_to_base(Fragments, "Emakefile"),
    SrcDirs = fragments_to_base(Fragments, "src"),
    EbinDirs = fragments_to_base(Fragments, "ebin"),
    InclDirs = fragments_to_base(Fragments, "include"),
    case shortest_sort(MakeDir++RebarDir++EmakeDir) of
        [] -> % precompiled dir?
            [{Path,_}|_] = most_instances(SrcDirs++EbinDirs++InclDirs),
            Path;
        [{Len,_}, {Len,_}] -> % it's a tie!
            [{Path,_}|_] = most_instances(SrcDirs++EbinDirs++InclDirs),
            Path;
        [{_, Path}|_] ->
            Path
    end.


%% -----------------------------------------------------------------------------
%% Internal API
%% -----------------------------------------------------------------------------
dispatch(Url, "text/html", Body, Srcdir, Libdir) ->
    Links = load_links(Body),
    Urls = lists:map(fun (Ur) -> join_url(Url, Ur) end, Links),
    lists:foldl(fun (Link_url, Acc) ->
                       Acc ++ load_url(Link_url, Srcdir, Libdir)
               end,
                [],
                Urls);
dispatch(_Url, "text/plain", Body, Srcdir, _Libdir) ->
    {match, [ModName|_]} = re:run(Body, "-module\\((.*)\\).",[{capture, all_but_first, list}]),
    ModPath = filename:join(Srcdir, ModName)++".erl",
    ok = file:write_file(ModPath, Body),
    [{module, ModPath}];
dispatch(_Url, Ct, Body, _Srcdir, Libdir)
  when Ct =:= "application/zip" orelse Ct =:= "application/octet-stream" ->
    {ok, Files} = zip:unzip(list_to_binary(Body), [{cwd, Libdir}]),
    [{app, guess_root(Files)}];
dispatch(Url, _Content_type, _Body, _Srcdir, _Libdir) ->
    [{unsupported_content_type, Url}].



load_links(Body) ->
    [_|_] = load_ls([mochiweb_html:parse(Body)]).

load_ls([]) ->
    [];
load_ls([Text]) when is_binary(Text) ->
    [];
load_ls([{<<"link">>, Attrs, _Text} | Rest]) ->
    case {proplists:lookup(<<"rel">>, Attrs),
          proplists:lookup(<<"href">>, Attrs)} of
        {{<<"rel">>, ?REL_ATTR},
         {<<"href">>, Url}}       -> [binary_to_list(Url) | load_ls(Rest)];
        {_, _}                    -> load_ls(Rest)
    end;
load_ls([{<<"a">>, Attrs, _Text} | Rest]) ->
    case {proplists:lookup(<<"rel">>, Attrs),
          proplists:lookup(<<"href">>, Attrs)} of
        {{<<"rel">>, ?REL_ATTR},
         {<<"href">>, Url}}       -> [binary_to_list(Url) | load_ls(Rest)];
        {_, _}                    -> load_ls(Rest)
    end;
load_ls([{_Tag, _Attrs, Content} | Rest]) ->
    load_ls(Content) ++ load_ls(Rest);
load_ls([_Other | Rest]) -> % html comments & other nodes
    load_ls(Rest).



remove_encoding({"content-type", Ct}) ->
    %% Right now we aren't concerning outselves with
    %% encoding since we are just passing the data
    %% through to the system
    {"content-type", erlang:hd(string:tokens(Ct, ";"))}.

fragments_to_base(Fragments, Pattern) ->
    [filename:join(lists:takewhile(fun(X) -> X =/= Pattern end, L)) ||
        L <- Fragments, lists:member(Pattern, L)].

shortest_sort(L) ->
    lists:sort([{length(P), P} || P <- L]).

most_instances(L) ->
    Dict = lists:foldl(fun(Path, Dict) ->
                           dict:update(Path, fun(X) -> X+1 end, 1, Dict)
                        end,
                        dict:new(),
                        L),
    lists:reverse(lists:keysort(2, dict:to_list(Dict))).

join_url(Base, Url) ->
    io:format("~p~n", [{Base, Url}]),
    case Url of
        "https://" ++ _ -> Url;
        "http://"  ++ _ -> Url;
        "/"        ++ _ -> {ok, Uri, []} = ex_uri:decode(Base),
                           ex_uri:encode(Uri#ex_uri{path = Url});
        _               -> string:strip(Base, right, $/) ++ "/" ++ Url
    end.
