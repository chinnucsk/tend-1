%%% Suite for testing the general behaviour of TEND
-module(tend_SUITE).
-include_lib("common_test/include/ct.hrl").
-compile(export_all).

all() ->
    [server_works, loading_lib_dirs, loader_test, guess_root,
     compile_module, load_module, zip_load].

%%% INITS
init_per_suite(Config) ->
    %% Start mock web server
    Port = 56789,
    application:start(cowboy),
    Dispatch = [
            %% {Host, list({Path, Handler, Opts})}
            {'_', [{'_', tend_SUITE_handler, ?config(data_dir, Config)}]}
            ],
    %% Name, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
    cowboy:start_listener(fake_server_listener, 5,
                          cowboy_tcp_transport, [{port, Port}],
                          cowboy_http_protocol, [{dispatch, Dispatch}]
                         ),
    %% Start the http client
    application:start(inets),
    [{base, "http://127.0.0.1:"++integer_to_list(Port)++"/"}
     | Config].

end_per_suite(Config) ->
    %% Kill mock web server
    application:stop(cowboy),
    Config.

init_per_testcase(loading_lib_dirs, Config) ->
    %% Make a lib_dir custom in priv/ to test if we boot while
    %% correctly loading libs.
    Priv = ?config(priv_dir, Config),
    LibDir = filename:join(Priv, "loading-lib-dirs_testdir/"),
    filelib:ensure_dir(LibDir++"/.ignore"),
    OriginalLibDir = application:get_env(tend, lib_dir),
    application:set_env(tend, lib_dir, LibDir),
    [{lib_dir, OriginalLibDir} | Config];
init_per_testcase(loader_test, Config) ->
    %% Make a lib_dir custom in priv/ to test if we boot while
    %% correctly loading libs.
    Priv = ?config(priv_dir, Config),
    LibDir = filename:join(Priv, "loader-test_testdir/"),
    filelib:ensure_dir(LibDir++"/.ignore"),
    OriginalLibDir = application:get_env(tend, lib_dir),
    application:set_env(tend, lib_dir, LibDir),
    {ok, Pid} = tend_sup:start_link(),
    [{lib_dir, OriginalLibDir},
     {sup, Pid}
     | Config];
init_per_testcase(load_module, Config) ->
    %% Make a lib_dir custom in priv/ to test if we boot while
    %% correctly loading libs.
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    application:start(inets),
    Priv = ?config(priv_dir, Config),
    LibDir = filename:join(Priv, "load-module_testdir/"),
    filelib:ensure_dir(LibDir++"/.ignore"),
    OriginalLibDir = application:get_env(tend, lib_dir),
    application:set_env(tend, lib_dir, LibDir),
    {ok, Pid} = tend_sup:start_link(),
    [{lib_dir, OriginalLibDir},
     {sup, Pid}
     | Config];
init_per_testcase(zip_load, Config) ->
    %% Make a lib_dir custom in priv/ to test if we boot while
    %% correctly loading libs.
    application:start(crypto),
    application:start(public_key),
    application:start(ssl),
    application:start(inets),
    Priv = ?config(priv_dir, Config),
    LibDir = filename:join(Priv, "zip-load_testdir/"),
    filelib:ensure_dir(LibDir++"/.ignore"),
    OriginalLibDir = application:get_env(tend, lib_dir),
    application:set_env(tend, lib_dir, LibDir),
    {ok, Pid} = tend_sup:start_link(),
    [{lib_dir, OriginalLibDir},
     {sup, Pid}
     | Config];
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(loading_lib_dirs, Config) ->
    application:set_env(tend, lib_dir, ?config(lib_dir, Config));
end_per_testcase(loader_test, Config) ->
    application:set_env(tend, lib_dir, ?config(lib_dir, Config)),
    Sup = ?config(sup, Config),
    unlink(Sup),
    exit(Sup, kill);
end_per_testcase(load_module, Config) ->
    application:set_env(tend, lib_dir, ?config(lib_dir, Config)),
    Sup = ?config(sup, Config),
    code:delete(tend_gist_load),
    code:purge(tend_gist_load),
    unlink(Sup),
    exit(Sup, kill);
end_per_testcase(zip_load, Config) ->
    application:set_env(tend, lib_dir, ?config(lib_dir, Config)),
    Sup = ?config(sup, Config),
    unlink(Sup),
    exit(Sup, kill);
end_per_testcase(_, Config) ->
    Config.

%%% ACTUAL TESTS

%% Preliminary test to make sure the test server works and is running
server_works(Config) ->
    BaseURI = ?config(base, Config),
    %ct:pal("~p", [httpc:request(BaseURI++"module/tend_test_mod.erl")]),
    %% Basic erl module
    {ok, 
     {{_HTTP, 200, _},
      _Headers,
      "-module(" ++ _}} = httpc:request(BaseURI++"module/tend_test_mod.erl"),
    %% Compiled module
    {ok, 
     {{_, 200, _},
      _,
      Beam}} = httpc:request(get, {BaseURI++"module/tend_test_mod.beam",[]}, [], [{body_format, binary}]),
    {ok, {_, [{abstract_code, _}]}} = beam_lib:chunks(Beam, [abstract_code]),
    %% Zip File
    {ok, 
     {{_, 200, _},
      _,
      Zip}} = httpc:request(get, {BaseURI++"module/tend_test_app.zip",[]}, [], [{body_format, binary}]),
    {ok, ZipList} = zip:unzip(Zip, [memory]),
    [{"tend_test_app/ebin/tend_test_app.app", _},
     {"tend_test_app/ebin/tend_test_mod.beam", _},
     {"tend_test_app/include/tend_test_app.hrl", _},
     {"tend_test_app/src/tend_test_mod.erl", _}] = lists:sort(ZipList),
    %% rebarized zip file
    {ok, 
     {{_, 200, _},
      _,
      RZip}} = httpc:request(get, {BaseURI++"module/zippers-0.1.zip",[]}, [], [{body_format, binary}]),
    {ok, RZipList} = zip:unzip(RZip, [memory]),
    [{"ferd-zippers-"++_, _},
     {"ferd-zippers-"++_, _} | _] = lists:sort(RZipList),
    %% .EZ archive
    {ok, 
     {{_, 200, _},
      _,
      Ez}} = httpc:request(get, {BaseURI++"module/tend_test_app.ez",[]}, [], [{body_format, binary}]),
    {ok, EzList} = zip:unzip(Ez, [memory]),
    [{"tend_test_app/ebin/tend_test_app.app", _},
     {"tend_test_app/ebin/tend_test_mod.beam", _},
     {"tend_test_app/include/tend_test_app.hrl", _},
     {"tend_test_app/src/tend_test_mod.erl", _}] = lists:sort(EzList),
    %% HTML page with links
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"html/erl"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"html/zip2"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"html/zip1"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"html/ez"),
    %% html page with hyperlinks (<a>)
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"ahtml/erl"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"ahtml/zip2"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"ahtml/zip1"),
    {ok, {{_, 200, _}, _,
      "<html>" ++ _}} = httpc:request(BaseURI++"ahtml/ez").

loading_lib_dirs(Config) ->
    %% fetching vars
    BaseURI = ?config(base, Config),
    Data = ?config(data_dir, Config),
    {ok, LibDir} = application:get_env(tend, lib_dir),
    %% preparing an OTP app to make sure we have the right ERL_LIBS behaviour
    zip:unzip(filename:join(Data, "zippers-0.1.zip"), [{cwd, LibDir}]),
    %% Start tend_sup: scan directories!
    {ok, Pid} = tend_sup:start_link(),
    %% Add a module to find in ebin if the paths are properly initialized
    {ok, 
     {{_, 200, _}, _,
      Beam}} = httpc:request(get, {BaseURI++"module/tend_test_mod.beam",[]}, [], [{body_format, binary}]),
    {ok, Ebin} = application:get_env(tend, ebin),
    file:write_file(filename:join(Ebin, "tend_test_mod.beam"), Beam),
    %% Search for all dirs to make sure stuff is right
    true = [] =/= [X || X <- code:get_path(), re:run(X, "zippers") =/= nomatch],
    true = [] =/= [X || X <- code:get_path(),
                        error =/= element(1,file:open(
                                    filename:join(X,"tend_test_mod.beam"),
                                    [read,raw]))
                  ],
    %% Kill the sup. Tiny clean up in case we succeed
    unlink(Pid),
    exit(Pid, kill).

loader_test(Config) ->
    BaseURI = ?config(base, Config),
    {ok, LibDir} = application:get_env(tend, lib_dir),
    {ok, Src} = application:get_env(tend, src),
    ct:pal("the vars are: ~p", [{LibDir, Src}]),
    ModName = filename:join(Src, "tend_test_mod.erl"),
    [{module, ModName}] = tend_loader:load_url(BaseURI ++ "html/erl",
                                               Src,
                                               LibDir),
    ok = file:delete(ModName),
    [{module, ModName}] = tend_loader:load_url(BaseURI ++ "ahtml/erl",
                                               Src,
                                               LibDir),
    AppPath = filename:join(LibDir, "tend_test_app"),
    [{app, AppPath}] = tend_loader:load_url(BaseURI ++ "module/tend_test_app.zip",
                                            Src,
                                            LibDir),
    ok = file:delete(ModName),
    os:cmd("rm -rf " ++ AppPath),
    Multi = tend_loader:load_url(BaseURI ++ "multihtml",
                                 Src,
                                 LibDir),
    {module, ModName} = proplists:lookup(module, Multi),
    {app,    AppPath} = proplists:lookup(app,    Multi).

guess_root(_Config) ->
    Batch1 = ["ferd-zippers-d646699/.gitignore",
              "ferd-zippers-d646699/Emakefile",
              "ferd-zippers-d646699/LICENSE",
              "ferd-zippers-d646699/Makefile",
              "ferd-zippers-d646699/README",
              "ferd-zippers-d646699/README.markdown",
              "ferd-zippers-d646699/doc/overview.edoc",
              "ferd-zippers-d646699/ebin/zippers.app",
              "ferd-zippers-d646699/include/.track-this-please",
              "ferd-zippers-d646699/priv/.track-this-please",
              "ferd-zippers-d646699/rebar",
              "ferd-zippers-d646699/src/zipper_bintrees.erl",
              "ferd-zippers-d646699/src/zipper_forests.erl",
              "ferd-zippers-d646699/src/zipper_lists.erl",
              "ferd-zippers-d646699/test/prop_zipper_bintrees.erl",
              "ferd-zippers-d646699/test/prop_zipper_forests.erl",
              "ferd-zippers-d646699/test/prop_zipper_lists.erl",
              "ferd-zippers-d646699/test/zipper_bintrees_tests.erl",
              "ferd-zippers-d646699/test/zipper_forests_tests.erl",
              "ferd-zippers-d646699/test/zipper_lists_tests.erl"],
    "ferd-zippers-d646699" = tend_loader:guess_root(Batch1),
    Batch2 = ["/home/user/code/ferd-zippers-d646699/.gitignore",
              "/home/user/code/ferd-zippers-d646699/Emakefile",
              "/home/user/code/ferd-zippers-d646699/LICENSE",
              "/home/user/code/ferd-zippers-d646699/Makefile",
              "/home/user/code/ferd-zippers-d646699/README",
              "/home/user/code/ferd-zippers-d646699/README.markdown",
              "/home/user/code/ferd-zippers-d646699/doc/overview.edoc",
              "/home/user/code/ferd-zippers-d646699/ebin/zippers.app",
              "/home/user/code/ferd-zippers-d646699/include/.track-this-please",
              "/home/user/code/ferd-zippers-d646699/priv/.track-this-please",
              "/home/user/code/ferd-zippers-d646699/rebar",
              "/home/user/code/ferd-zippers-d646699/src/zipper_bintrees.erl",
              "/home/user/code/ferd-zippers-d646699/src/zipper_forests.erl",
              "/home/user/code/ferd-zippers-d646699/src/zipper_lists.erl",
              "/home/user/code/ferd-zippers-d646699/test/prop_zipper_bintrees.erl",
              "/home/user/code/ferd-zippers-d646699/test/prop_zipper_forests.erl",
              "/home/user/code/ferd-zippers-d646699/test/prop_zipper_lists.erl",
              "/home/user/code/ferd-zippers-d646699/test/zipper_bintrees_tests.erl",
              "/home/user/code/ferd-zippers-d646699/test/zipper_forests_tests.erl",
              "/home/user/code/ferd-zippers-d646699/test/zipper_lists_tests.erl"],
    "/home/user/code/ferd-zippers-d646699" = tend_loader:guess_root(Batch2),
    Batch3 = ["code/ferd-zippers-d646699/.gitignore",
              "code/ferd-zippers-d646699/Emakefile",
              "code/ferd-zippers-d646699/LICENSE",
              "code/ferd-zippers-d646699/Makefile",
              "code/ferd-zippers-d646699/README",
              "code/ferd-zippers-d646699/README.markdown",
              "code/ferd-zippers-d646699/doc/overview.edoc",
              "code/ferd-zippers-d646699/ebin/zippers.app",
              "code/ferd-zippers-d646699/include/.track-this-please",
              "code/ferd-zippers-d646699/priv/.track-this-please",
              "code/ferd-zippers-d646699/rebar",
              "code/ferd-zippers-d646699/src/zipper_bintrees.erl",
              "code/ferd-zippers-d646699/src/zipper_forests.erl",
              "code/ferd-zippers-d646699/src/zipper_lists.erl",
              "code/ferd-zippers-d646699/test/prop_zipper_bintrees.erl",
              "code/ferd-zippers-d646699/test/prop_zipper_forests.erl",
              "code/ferd-zippers-d646699/test/prop_zipper_lists.erl",
              "code/ferd-zippers-d646699/test/zipper_bintrees_tests.erl",
              "code/ferd-zippers-d646699/test/zipper_forests_tests.erl",
              "code/ferd-zippers-d646699/test/zipper_lists_tests.erl"],
    "code/ferd-zippers-d646699" = tend_loader:guess_root(Batch3).

compile_module(Config) ->
    Priv = ?config(priv_dir, Config),
    Unique = lists:flatten(io_lib:format("~p",[make_ref()])),
    Mod = "-module(compile_mod_test_mod). "
          "-export([main/0]). "
          "main() -> \"" ++ Unique ++ "\". ",
    Path = filename:join(Priv, "compile_mod_test_mod.erl"),
    file:write_file(Path, Mod),
    tend_compile_module:compile(Path, Priv),
    code:add_patha(Priv),
    Unique = compile_mod_test_mod:main().

%% milestone! Can load modules remotely + SSL
load_module(_Config) ->
    {'EXIT',{undef,_}} = (catch tend_gist_load:run()),
    ok = tend:load("https://raw.github.com/gist/3068457/8b99cc3f4b7cac3fcd19c4b0a0b4f0bfde7660e8/tend_gist_load.erl"),
    ':)' = tend_gist_load:run().

zip_load(_Config) ->
    %% Must load 3 applications, all with different compile methods.
    %% regis from LYSE uses Emakefiles
    {'EXIT',{undef,_}} = (catch regis:module_info()),
    tend:load("http://learnyousomeerlang.com/static/erlang/regis-1.1.0.zip"),
    regis:module_info(), % no crash for undef
    %% dispcount uses a makefile and has rebar deps for proper
    {'EXIT',{undef,_}} = (catch dispcount:module_info()),
    {'EXIT',{undef,_}} = (catch proper:module_info()),
    tend:load("https://github.com/ferd/dispcount/zipball/v0.1.0"),
    dispcount:module_info(),
    proper:module_info(),
    %% blogerl uses only a local rebar copy, but also has an unusual
    %% directory structure. Erlydtl is a dependency of blogerl.
    {'EXIT',{undef,_}} = (catch blog:module_info()),
    {'EXIT',{undef,_}} = (catch erlydtl:module_info()),
    tend:load("https://bitbucket.org/ferd/blogerl/get/5d823822dbe0.zip"),
    blog:module_info(),
    erlydtl:module_info(),
    %% erlpass uses raw rebar and depends on bcrypt, which runs as a NIF
    {'EXIT',{undef,_}} = (catch bcrypt:module_info()),
    {'EXIT',{undef,_}} = (catch erlpass:module_info()),
    tend:load("https://github.com/ferd/erlpass/zipball/0.1.2"),
    application:start(bcrypt),
    <<_/binary>> = erlpass:hash("it works!!"),
    %% Downloading an app that has only a rebar.config file.
    {'EXIT',{undef,_}} = (catch jsx:module_info()),
    tend:load("https://github.com/talentdeficit/jsx/zipball/v1.3.1"),
    jsx:module_info().
