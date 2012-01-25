%% Copyright (c) 2011 Robert Virding. All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%% 1. Redistributions of source code must retain the above copyright
%%    notice, this list of conditions and the following disclaimer.
%% 2. Redistributions in binary form must reproduce the above copyright
%%    notice, this list of conditions and the following disclaimer in the
%%    documentation and/or other materials provided with the distribution.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.

%% File    : tcp_io_server.erl
%% Author  : Robert Virding
%% Purpose : An io-server which interfaces to a TCP socket.

%% Implement a standard io-server which interfaces to a TCP socket. It
%% sets the socket in active once mode to allow concurrent reading and
%% writing. Basically there no options which can be set while it is
%% running.

-module(tcp_io_server).

-export([start/1,start_link/1,server/1,stop/1]).

-export([demo/1,shell_demo/1]).

-record(st, {sock,ibuf=[],eof=false}).

%% start(Socket) -> {ok,IoServer}.
%% start_link(Socket) -> {ok,IoServer}.
%%  Start an io-server which is connected to Socket in a new process.
%%  The io-server process becomes the new controlling process for that
%%  socket as we use active once for receiving data from the
%%  socket. We temporarily set the socket in active false so as to
%%  lessen the risk of losing packets.

start(Socket) ->
    inet:setopts(Socket, [{active,false}]),
    Io = spawn(tcp_io_server, server, [Socket]),
    ok = gen_tcp:controlling_process(Socket, Io),
    {ok,Io}.

start_link(Socket) ->
    inet:setopts(Socket, [{active,false}]),
    Io = spawn_link(tcp_io_server, server, [Socket]),
    ok = gen_tcp:controlling_process(Socket, Io),
    {ok,Io}.

stop(Io) when is_pid(Io) ->
    Ref = send_tcp_request(Io, stop),
    wait_tcp_reply(Ref);
stop(_) -> erlang:error(badarg).    

%% server(Socket) -> ok | {error,Reason}.
%%  Start the current process as an io-server interfacing Socket. It
%%  is assumed to already be the controlling process for that socket.

server(Socket) ->
    inet:setopts(Socket, [{active,once}]),	%We use active once
    server_loop(#st{sock=Socket}).

%% server_loop(Status) -> ok | {error,Reason}.
%%  The main server loop.

server_loop(St0) ->
    receive
	{io_request,From,ReplyAs,Req} ->
	    case io_request(Req, St0) of
		{ok,Rep,St1} ->
		    io_reply(From, ReplyAs, Rep),
		    server_loop(St1);
		{error,Rep,St1} ->
		    io_reply(From, ReplyAs, Rep),
		    server_loop(St1);
		{stop,Reason,_} ->
		    io_reply(From, ReplyAs, Reason)
	    end;
	{tcp_request,From,ReplyAs,Req} ->
	    case tcp_request(Req, St0) of
		{ok,Rep,St1} ->
		    tcp_reply(From, ReplyAs, Rep),
		    server_loop(St1);
		{error,Rep,St1} ->
		    tcp_reply(From, ReplyAs, Rep),
		    server_loop(St1);
		{stop,Reason,_} ->
		    tcp_reply(From, ReplyAs, Reason)
	    end;
	Other when not is_tuple(Other) ; element(1, Other) =/= tcp ->
	    %% Ignore unknown messages not from tcp.
	    io:format("Ignoring: ~p\n", [Other]),
	    server_loop(St0)
    end.

%% io_reply(From, ReplyAs, Reply) -> term().
%% tcp_reply(From, ReplyAs, Reply) -> term().
%%  Send replies back to requesters.

io_reply(From, ReplyAs, Rep) ->
    From ! {io_reply,ReplyAs,Rep}.

tcp_reply(From, ReplyAs, Rep) ->
    From ! {tcp_reply,ReplyAs,Rep}.

%% tcp_request(Req, State) -> {ok,Rep,St} | {error,Rep,st} | {stop,Rep,St}.
%%  Handle tcp server requests.

tcp_request(stop, St) -> {stop,ok,St};
tcp_request(_, St) -> {error,{error,enotsup},St}.

%% io_request(Req, State) -> {ok,Rep,St} | {error,Rep,St} | {stop,Rep,St}.
%%  Handle io server requests.

%% Output requests.
io_request({put_chars,Enc,Chars}, St) ->
    put_chars(Enc, Chars, St);
io_request({put_chars,Enc,M,F,As}, St) ->
    put_chars(Enc, M, F, As, St);
%% Input requests, use functions in io_lib which handle encoding.
io_request({get_until,Enc,Prompt,M,F,As}, St) ->
    get_until(Enc, Prompt, io_lib, get_until, [{M,F,As}], St);
io_request({get_chars,Enc,Prompt,N}, St) ->
    get_until(Enc, Prompt, io_lib, collect_chars, [N], St);
io_request({get_line,Enc,Prompt}, St) ->
    get_until(Enc, Prompt, io_lib, collect_line, [], St);
%% Server requests.
io_request({get_geometry,_}, St) -> {error,{error,enotsup},St};
io_request({setopts,_}, St) -> {error,{error,enotsup},St};
io_request(getopts, St) -> {ok,[],St};
%% Multiple requests.
io_request({requests,Reqs}, St) ->
    io_requests(Reqs, {ok,ok,St});
%% The old encoding-less forms.
io_request({put_chars,Chars}, St) ->
    io_request({put_chars,latin1,Chars}, St);
io_request({put_chars,M,F,As}, St) ->
    io_request({put_chars,latin1,M,F,As}, St);
io_request({get_until,Prompt,M,F,As}, St) ->
    io_request({get_until,latin1,Prompt,M,F,As}, St);
io_request({get_chars,Prompt,N}, St) ->
    io_request({get_chars,latin1,Prompt,N}, St);
io_request({get_line,Prompt}, St) ->
    io_request({get_line,latin1,Prompt}, St);
%% Nothing we recognise.
io_request(R, St) -> {error,{error,{request,R}},St}.

%%io_requests(Reqs, Result) -> Result.

io_requests([R|Rs], {ok,_,St}) ->
    io_requests(Rs, io_request(R, St));
io_requests([_|_], Error) -> Error;
io_requests([], Res) -> Res.

put_chars(Enc, Cs, St) ->
    Bs = unicode:characters_to_list(Cs, Enc),
    case gen_tcp:send(St#st.sock, Bs) of
	ok -> {ok,ok,St};
	{error,_} -> {error,{error,put_chars},St}
    end.

put_chars(Enc, M, F, As, St) ->
    case catch apply(M, F, As) of
	{'EXIT',_} -> {error,{error,F},St};
	Cs -> put_chars(Enc, Cs, St)
    end.

%% get_until(Enc, Prompt, M, F, As, #st{ibuf=eof}=St) ->
%%     prompt(Sock, Prompt),
%%     {ok,eof,St};
%% get_until(Enc, Prompt, M, F, As, #st{sock=Sock,ibuf=Buf}=St) ->
%%     prompt(Sock, Prompt),			%Output the prompt
%%     case get_until_apply([], Buf, Enc, M, F, As) of
%% 	{done,Ret,Rest} ->
%% 	    {ok,Ret,St#st{ibuf=Rest}};
%% 	{more,Cont} ->
%% 	    get_until_loop(Sock, Cont, Enc, M, F, As, St);
%% 	{error,_} ->
%% 	    {error,{error,F},St}
%%     end.

get_until(Enc, Prompt, M, F, As, #st{sock=Sock,ibuf=Buf}=St) ->
    prompt(Sock, Prompt),			%Output the prompt
    if Buf =:= eof -> {ok,eof,St};
       Buf =:= [] ->
	    %% No chars in buffer, straight to the loop.
	    get_until_loop(Sock, [], Enc, M, F, As, St);
       true ->
	    %% First try with what we have got.
	    get_until_step(Sock, [], Buf, Enc, M, F, As, St)
    end.

get_until_step(Sock, Cont0, Chars, Enc, M, F, As, St) ->
    case get_until_apply(Cont0, Chars, Enc, M, F, As) of
	{done,Ret,Rest} ->
	    {ok,Ret,St#st{ibuf=Rest}};
	{more,Cont1} ->
	    get_until_loop(Sock, Cont1, Enc, M, F, As, St);
	{error,_} ->
	    {error,{error,err_func(M, F, As)},St}
    end.

get_until_loop(Sock, Cont0, Enc, M, F, As, St) ->
    receive
	{tcp,Sock,Chars} ->
	    %% Reset active once to get next message.
	    inet:setopts(Sock, [{active,once}]),
	    get_until_step(Sock, Cont0, Chars, Enc, M, F, As, St);
	{tcp_closed,Sock} ->
	    %% Socket closed, one last try with 'eof'.
	    case get_until_apply(Cont0, eof, Enc, M, F, As) of
		{done,Ret,Rest} -> {ok,Ret,St#st{ibuf=Rest}};
		{error,_} -> {stop,{error,err_func(M, F, As)},St#st{ibuf=eof}};
		{more,_} -> {stop,{error,err_func(M, F, As)},St#st{ibuf=eof}}
	    end;
	{tcp_error,sock,Reason} ->
	    {error,{error,Reason},St};
	%% Allow duplex mode for output
	{io_request,From,ReplyAs,{put_chars,EncP,Cs}} ->
	    get_until_put(Sock, Cont0, Enc, M, F, As,
			  From, ReplyAs, put_chars(EncP, Cs, St));
	{io_request,From,ReplyAs,{put_chars,EncP,M,F,As}} ->
	    get_until_put(Sock, Cont0, Enc, M, F, As,
			  From, ReplyAs, put_chars(EncP, M, F, As, St))
    end.

get_until_put(Sock, Cont, Enc, M, F, As, From, ReplyAs, Res) ->
    case Res of
	{ok,Ret,St} ->
	    io_reply(From, ReplyAs, Ret),
	    get_until_loop(Sock, Cont, Enc, M, F, As, St);
	{error,Error,St} ->
	    io_reply(From, ReplyAs, Error),
	    get_until_loop(Sock, Cont, Enc, M, F, As, St)
    end.
    
%% get_until_apply(Continuation, Buffer, Encoding, M, F, Args) ->
%%     {done,Return,Rest} | {more,Continuation} | {error,Reason}.
%%  We KNOW this calls the io_lib functions so we convert their broken
%%  return values to the old version (which is not broken).

get_until_apply(Cont0, Buf, Enc, M, F, As) ->
    case catch apply(M, F, [Cont0,Buf,Enc|As]) of
	%% The older better return values.
	{done,_,_}=Done -> Done;
	{error,_}=Error -> Error;
	{more,_}=More -> More;
	%% The newer broken return values.
	{stop,Ret,Rest} -> {done,Ret,Rest};
	{'EXIT',Reason} -> {error,Reason};
	Cont1 -> {more,Cont1}
    end.

err_func(io_lib, get_until, [{_,F,_}]) -> F;
err_func(_, F, _) -> F.

%% prompt(Socket, Prompt) -> ok | {error,Error}.

prompt(_, '') -> ok;
prompt(Sock, Prompt) ->
    Cs = io_lib:format_prompt(Prompt),
    gen_tcp:send(Sock, Cs).

%% Functions for communicating with a tcp io server.
%%  The messages sent have the following formats:
%%
%%	{tcp_request,From,ReplyAs,Request}
%%	{tcp_reply,ReplyAs,Reply}

send_tcp_request(Io, Request) ->
    Ref = erlang:monitor(process, Io),
    Io ! {tcp_request,self(),Ref,Request},
    Ref.

wait_tcp_reply(Ref) ->
    receive
	{tcp_reply,Ref,Reply} ->
	    erlang:demonitor(Ref, [flush]),	%Remove the monitor and flush
	    %% receive {'EXIT', From, _} -> ok after 0 -> ok end,
	    Reply;
	{'DOWN', Ref, _, _, _} ->
	    %% receive {'EXIT', From, _} -> ok after 0 -> ok end,
	    {error,terminated}
    end.

%% Test/demo functions.

%% demo(Port) -> {ok,ListenSocket,Socket,IoServer}.
%%  Open a listen socket, wait for a connection then start a io-server
%%  for that connection. Io requests can be made to the server.

demo(Port) ->
    {ok,Ls} = gen_tcp:listen(Port, []),
    {ok,S} = gen_tcp:accept(Ls),
    {ok,Io} = tcp_io_server:start_link(S),
    {ok,Ls,S,Io}.

%% shell_demo(Port) -> {ok,ListenSocket}.
%%  Open a listen socket and starts a shell for each connection which
%%  uses that socket for its standard io. All io to/from the shell and
%%  its sub-processes will now be sent across the socket.

shell_demo(Port) ->
    {ok,Ls} = gen_tcp:listen(Port, []),
    spawn_link(fun () -> shell_accept(Ls) end),
    {ok,Ls}.

shell_accept(Ls) ->
    {ok,S} = gen_tcp:accept(Ls),
    spawn(fun () -> shell_accept(Ls) end),
    {ok,Io} = tcp_io_server:start_link(S),
    group_leader(Io, self()),
    shell:server(true, false).
