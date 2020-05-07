program webserver;

uses sockets, sysutils, strutils;

label restart;

var
  address  : TInetSockAddr;
  mysock   : longint;
  asock    : longint;
  homedir  : string;
  dir      : string;
  line     : string;
  outstr   : text;
  instr    : text;
  request  : text;
  reqsize  : longint;
  log      : text;
  validreq : boolean;
  vrestart : boolean;
  types    : array [0..5] of array [0..1] of string;
{Variables read from file jeff.conf}
  conf : record
    ip        : string;
    port      : integer;
    webmaster : string;
    logfile   : string;
    indexfile : string;
    chroot    : string;
    errdir    : string;
    password  : string;
    verbosity : integer;
  end;


{****************************************************************************************************************************************************}

procedure Fatalerror(message : string);
	var n : integer;
	begin
	n := IOResult;
		{$I-}
		writeln(log, '###################################FATAL ERROR###################################');
		writeln(log, '#################################################################################');
		writeln(log, message);
		writeln(log, 'Details:');
		writeln(log, 'Socket error code: ', SocketError);
		writeln(log, 'IO error code: ', n);
		writeln(stderr, '###################################FATAL ERROR###################################');
		writeln(stderr, '#################################################################################');
		writeln(stderr, message);
		writeln(stderr, 'Details:');
		writeln(stderr, 'Socket error code: ', SocketError);
		{$I+}
		close(log);
		readln();
		halt();
	end;

{****************************************************************************************************************************************************}

procedure logme(logtext : string ; verb : integer);
	begin
	if conf.verbosity >= verb then
		begin
		{$I-}
		writeln(log, logtext);
		{I+}
		end;
	if conf.verbosity >= verb + 1 then
		begin
		writeln(logtext);
		end;
	end;

{****************************************************************************************************************************************************}

procedure OpenLogFile(logfile : string);
	begin
	assign(log, logfile);
	{$I-}
	append(log);
	{$I+}
	if IOResult <> 0 then
		begin
		{$I-}
		rewrite(log);
		{$I+}
		logme(concat('Logfile ', logfile, ' created.'), 2);
		end;
	if IOResult <> 0 then
		Fatalerror('Could not open/create log file.');
	end;

{****************************************************************************************************************************************************}

procedure LoadContentTypes();
	begin
	types[0,0] := 'html';
	types[0,1] := 'text/html';
	types[1,0] := 'htm';
	types[1,1] := 'text/html';
	types[2,0] := 'gif';
	types[2,1] := 'image/gif';
	types[3,0] := 'jpg';
	types[3,1] := 'image/jpeg';
	types[4,0] := 'jpeg';
	types[4,1] := 'image/jpeg';
	types[5,0] := 'txt';
	types[5,1] := 'text/plain';
	end;

{****************************************************************************************************************************************************}

procedure InitialLog();
	var
		tmpstr : string;
	begin
	OpenLogFile(conf.logfile);
	logme(concat('Server started on ', DateTimeToStr(Now())), 0);
	logme(concat('Logfile ''', conf.logfile, ''' opened.'), 2);
	logme('Settings loaded:', 2);
	logme(concat('Directory:            ', conf.chroot), 0);
	logme(concat('IP:                   ', conf.ip), 2);
	str(conf.port, tmpstr);
	logme(concat('Port:                 ', tmpstr), 2);
	logme(concat('Webmaster''s email:    ', conf.webmaster), 2);
	logme(concat('Log-file:             ', conf.logfile), 2);
	logme(concat('Indexing file:        ', conf.indexfile), 2);
	logme(concat('Errorpages directory: ', conf.errdir), 2);
	logme(concat('RM password:          ', conf.password), 2);
	str(conf.verbosity, tmpstr);
	logme(concat('Degree of verbosity:  ', tmpstr), 2);
	logme('                      Do you expect me to talk?', 150);
	end;

{****************************************************************************************************************************************************}

procedure getInformation(conffilename : string);
	var
		conffile : text;
		tmp1 	 : integer;
		tmp2	 : word;
		n        : integer;
	begin
	getdir(0, homedir);
	conf.chroot := homedir;
	conf.ip := '127.0.0.1';
	conf.port := 80;
	conf.logfile := 'jeff.log';
	conf.indexfile := 'index.html';
	conf.verbosity := 10;
	conf.webmaster := '';
	conf.errdir := '';
	conf.password := '';
	{std value for webmaster is defined at end of procedure depending on ip}
	{$I-}
	assign(conffile, conffilename);
	reset(conffile);
	{$I+}
	n := IOResult;
	if n <> 0 then
		begin
		writeln(stderr, 'Configuration file ''', conffilename, ''' not found.');
		writeln(stderr, 'Loading standard configuration.');
		end
	else
		begin
		while not eof(conffile) do
			begin
			readln(conffile, line);
			if pos('ip: ', LowerCase(line)) = 1 then
				conf.ip := RightStr(line, length(line)-4);
			
			if pos('port: ', LowerCase(line)) = 1 then
				begin
				val(RightStr(line, length(line)-6), tmp1, tmp2);
				conf.port := tmp1;
				end;
			
			if pos('verbosity: ', LowerCase(line)) = 1 then
				begin
				val(RightStr(line, length(line)-11), tmp1, tmp2);
				conf.verbosity := tmp1;
				end;
	
			if pos('mastermail: ', LowerCase(line)) = 1 then
				conf.webmaster := RightStr(line, length(line)-12);
			
			if pos('logfile: ', LowerCase(line)) = 1 then
				conf.logfile := RightStr(line, length(line)-9);
			
			if pos('index: ', LowerCase(line)) = 1 then
				conf.indexfile := RightStr(line, length(line)-7);
			
			if pos('path: ', LowerCase(line)) = 1 then
				conf.chroot := RightStr(line, length(line)-6);

			if pos('errordir: ', LowerCase(line)) = 1 then
				conf.errdir := RightStr(line, length(line)-10);

			if pos('rmpass: ', LowerCase(line)) = 1 then
				conf.password := RightStr(line, length(line)-8);
			end;
		close(conffile);
		end;
	if conf.webmaster = '' then
		conf.webmaster := concat('webmaster@', conf.ip);
	if conf.errdir = '' then
		conf.errdir := concat(conf.chroot, '\errors');
	end;

{****************************************************************************************************************************************************}

procedure initialiseSocket();
	begin
	mysock := socket(af_inet, sock_stream, 0);
	if((mysock = -1) or (socketerror <> 0)) then
		begin
		FatalError('An error has occurred during the creation of the socket.');
		end;
	logme('Socket created.', 8);
	address.sin_family := af_inet;
 	address.sin_port   := htons(conf.port);
  	address.sin_addr   := StrToNetAddr(conf.ip);
	if ((not bind(mysock, address, sizeof(address))) or (socketerror <> 0)) then
		begin
		FatalError('An error has occurred during the binding of the socket to an IP address and a port.');
		end;
	logme('Socket binded.', 8);
	if ((not listen(mysock, 0)) or (socketerror <> 0)) then
		begin
		FatalError('An error occurred when trying to listen.');
		end;
	logme('Socket is now listening.', 8);
	logme('Socket initialised.', 8);
	end;

{****************************************************************************************************************************************************}

procedure Wait4Requests();
	var
		len     : longint;
		portstr : string;
	begin
	len := sizeof(address);
	logme('', 4);
	logme('Waiting for incoming connections...', 4);
  	asock := accept(mysock, address, len);
  	if socketerror <> 0 then
        	begin
		FatalError('An error has occurred after the binding of the socket to an address and a port.');
		end;
	str(address.sin_port, portstr);
  	logme(concat('Incoming connection from ', NetAddrToStr(address.sin_addr), ':', portstr, ' on ', DateTimeToStr(Now())), 3);
	
	sock2text(asock, instr, outstr);
  	if socketerror <> 0 then
   	     FatalError('An error occurred while converting the socket to a virtual file.');
	logme('Socket converted into virtual file.', 8);
 	reset(instr);
 	rewrite(outstr);
	end;

{****************************************************************************************************************************************************}

procedure CloseConnection();
	begin
	logme('Closing connection', 8);
	{$I-}
	shutdown(asock, 2);
  	close(instr);
	{$I+}
	if IOResult <> 0 then
		logme('Connection couldn''t be closed (again).', 4);
	logme('Connection closed', 8);
	end;

{****************************************************************************************************************************************************}

function send(data : string) : boolean;
	begin
	send := true;
	logme(concat('> ', data), 8);
	{$I-}
	writeln(outstr, data);
	{$I+}
	if IOResult <> 0 then
		begin
		logme('This line could not be sent because the connection was reset.', 6);
		closeconnection();
		send := false;
		end;
	end;

{****************************************************************************************************************************************************}

function GetContentType() : string;
	var
		ext   : string;
		tmp   : integer;
		i     : integer;
	begin
	tmp := pos('.', line);
	ext := line;
	delete(ext, 1, tmp);
	ext := LowerCase(ext);
	logme(concat('File extension: ', ext), 8);
	GetContentType := '';
	for i:= 0 to 5 do
		if types[i][0] = ext then
			GetContentType := types[i][1];
	if GetContentType = '' then
		GetContentType := 'application/octet-stream';
	logme(concat('Content-Type set to ', GetContentType), 8);
	end;

{****************************************************************************************************************************************************}

procedure HTTPHeader(code : integer; description : string; contlen : longint);
	var
		tmp : string;
		sth : boolean;
	begin
	sth := true;
	str(code, tmp);
	sth := send(concat('HTTP/1.1 ', tmp, ' ', description))
	AND send('Server: Jeff Hemmen - School project web server 0.8');
	str(contlen, tmp);
	sth := sth AND send(concat('Content-Length: ', tmp));
	send('Connection: Keep-Alive');
	if code = 200 then
		begin
		sth := sth AND send(concat('Content-Type: ', GetContentType()));
		end
	else
		begin
		sth := sth AND send('Content-Type: text/html');
		end;
	end;


{****************************************************************************************************************************************************}

procedure SendRequest(code : integer; description : string);
	begin
	logme('Sending Request', 8);
	HTTPHeader(code, description, reqsize);
	send('');
	while not eof(request) do
		begin
		{$I-}
		readln(request, line);
		{$I+}
		if IOResult <> 0 then
			Fatalerror('Error reading requested file!');
		send(line);
		end;
	end;

{****************************************************************************************************************************************************}

procedure HTTPError(code : integer; description : string);
	var
		errorfile : text;
		just4size : file of byte;
		errfname  : string;
		codestr   : string;
		tmpdir    : string;
		n         : integer;
		n1        : integer;
	begin
	str(code, codestr);
	logme(concat('Sending HTTP-Error ', codestr, ': ', description), 8);
	errfname := concat(codestr, '.html');
	{$I-}
	chdir(conf.errdir);
	{$I+}
	n := IOResult;
	if n = 0 then
		begin
		getdir(0, tmpdir);
		logme(concat('Changed to directory ', tmpdir), 8);
			assign(just4size, errfname);
			{$I-}
			reset(just4size);
			{$I+}
			reqsize := 0;
			if IOResult = 0 then
				begin
				reqsize := filesize(just4size);
				close(just4size);
				end;
		assign(request, errfname);
		{$I-}
		reset(request);
		{$I+}
		end;
	n1 := IOResult;
	if ((n <> 0) OR (n1 <> 0)) then
		begin
		logme('Sending std error message', 8);
		HTTPHeader(code, description, 215+2*length(description)+length(conf.webmaster));
		send('');
		logme('', 6);
		if send(concat('<html><head><title>Error ', codestr, ': ', description, '</title></head>'))
		AND send(concat('<body><h1>An error occurred:<p></h1><h3><u>Details</u>:<br>', codestr, ': ', description, '</h3>'))
		AND send(concat('<p>&nbsp;<p>Please contact the '))
		AND send(concat('<a href=''mailto:', conf.webmaster, '''>webmaster</a>'))
		AND send(concat(' if you think you should do so.'))
		then closeconnection();
		end
	else	{errorfile exists}
		begin
		SendRequest(code, description);
		close(request);
		CloseConnection();
		end;
	end;

{****************************************************************************************************************************************************}

function RootRequested() : boolean;
	begin
	RootRequested := (line = '');
	end;

{****************************************************************************************************************************************************}

procedure GetDirectory();
	var
		tmp1 : integer;
		tmp2 : integer;
		tmp3 : string;
	begin
	tmp1 := 0;
	tmp3 := line;
	while(true) do
		begin
		tmp2 := pos('\', tmp3);
		if tmp2 <> 0 then
			begin
			tmp1 := tmp1 + tmp2;
			delete(tmp3, 1, tmp2);
			end
		else
			break;
		end;
	{tmp1 now contains the position of the last occurence of '\' in line}
	dir := copy(line, 1, tmp1);
	delete(line, 1, tmp1);
	logme(concat('Requested file path: ', dir), 6);
	logme(concat('Requested file name: ', line), 6);
	end;
{****************************************************************************************************************************************************}

function chgDirectory() : boolean;
	begin
	{$I-}
	chdir(dir);
	{$I+}
	if IOResult <> 0 then
		begin
		logme('Directory changed!', 8);
		chgDirectory := false;
		end
	else
		begin
		logme('Directory changed!', 8);
		chgDirectory := true;
		end;
	end;

{****************************************************************************************************************************************************}

function OpenRequest() : boolean;
	var
		size      : longint;
		just4size : file of byte;
		tmp       : string;
	begin
	logme('Opening requested file.', 8);
	OpenRequest := false;
	assign(just4size, line);
	{$I-}
	reset(just4size);
	{$I+}
	size := 0;
	if IOResult = 0 then
		begin
		size := filesize(just4size);
		close(just4size);
		end;
	assign(request, line);
	{$I-}
	reset(request);
	{$I+}
	if IOResult = 0 then
		begin
		OpenRequest := true;
		logme('Requested file opened.', 8);
		reqsize := size;
		end;
	end;

{****************************************************************************************************************************************************}

procedure rootElse403();
	begin
	line := conf.indexfile;
	logme('Root requested', 8);
	logme(concat('Trying to open ''', line, ''' ...'), 8);
	if not OpenRequest() then
		begin
		logme('Failed -> Error 403: Forbidden', 8);
		HTTPError(403, 'Forbidden');
		end
	else
		begin
		logme('Succeeded!', 8);
		sendRequest(200, 'OK');
		close(request);
		end;
	end;

{****************************************************************************************************************************************************}

procedure LinuxPath2WinPath();
	var
		tmp     : integer;
		hexcode : string;
		hexstr  : string;
	begin
	logme('Converting request', 8);
	line := AnsiReplaceStr(line, '/', '\');
	tmp := pos('%', line);
	while not tmp = 0 do
		begin
		hexcode[1] := line[tmp+1];
		hexcode[2] := line[tmp+2];
		str(hex2dec(hexcode), hexstr);
		delete(line, tmp, 3);
		insert(hexstr, line, tmp);
		tmp := pos(line, '%');
		end;
		delete(line, 1, 1);	//remove initial '\'
	logme(concat('Requested item: ', line), 8);
	end;

{****************************************************************************************************************************************************}

procedure treatJEFF();
	var
		phrase   : string;
		action   : string;
		value    : string;
		swapfile : string;
		pass     : string;
	begin
	phrase := 'Not empty';
	action := '';
	pass := '';
	if conf.password = '' then
		begin
		send('Remote Management disabled.');
		exit;
		end;
	while phrase <> '' do
		begin
		readln(instr, phrase);
		phrase := LowerCase(phrase);
		if pos('action: ', phrase) = 1 then
				action := RightStr(phrase, length(phrase)-8);
		if pos('value: ', phrase) = 1 then
				value := RightStr(phrase, length(phrase)-7);
		if pos('pass: ', phrase) = 1 then
				pass := RightStr(phrase, length(phrase)-6);
		if pos('file: ', phrase) = 1 then
				swapfile := RightStr(phrase, length(phrase)-6);
		logme(concat('> ', phrase), 6);
		end;
	logme(concat('Action:   ', action), 6);
	logme(concat('Value:    ', value), 6);
	logme(concat('File:     ', swapfile), 6);
	logme(concat('Password: ', pass), 6);
	if pass <> conf.password then
		begin
		send('Wrong password');
		send('');
		CloseConnection();
		exit();
		end;
	send('Password OK');
	if LowerCase(action) = 'reload' then
		begin
		if LowerCase(value) = 'conf' then
			begin
			chdir(homedir);
			GetInformation('jeff.conf');
			chdir(conf.chroot);
			send('Configuration reloaded');
			send('');
			end;
		if LowerCase(value) = 'contenttypes' then
			begin
			{!!}{to implement later}
			send('Contenttypes not reloadable yet');
			send('');
			end;
		end;
	if LowerCase(action) = 'shutdown' then
		begin
		if LowerCase(value) = 'halt' then
			begin
			send('Shutting down...');
			send('');
			CloseConnection();
			CloseSocket(mysock);
			logme('Socket closed.', 8);
			close(log);
			writeln('Log file closed.');
			writeln('Server halted');
			halt();
			end;
		if LowerCase(value) = 'restart' then
			begin
			send('Shutting down ...');
			send('');
			CloseConnection();
			CloseSocket(mysock);
			logme('Socket closed.', 8);
			close(log);
			writeln('Log file closed.');
			writeln('Restarting server ...');
			vrestart := true;
			end;
		end;
	if LowerCase(action) = 'swap' then
		begin
		if LowerCase(value) = 'conf' then
			begin
			if swapfile = '' then
				begin
				send('Missing file name!');
				send('');
				closeConnection();
				exit;
				end
			else
				begin
				chdir(homedir);
				logme('Swapping configuration file.', 6);
				logme(concat('New conf file: ''', swapfile, ''''), 6);
				getInformation(swapfile);
				chdir(conf.chroot);
				end;
			end;
		if LowerCase(value) = 'log' then
			begin
			if swapfile = '' then
				begin
				send('Missing file name!');
				send('');
				closeConnection();
				exit;
				end
			else
				begin
				chdir(homedir);
				logme('Swapping logfile.', 2);
				logme(concat('New logfile: ''', swapfile, ''''), 2);
				flush(log);
				close(log);
				OpenLogFile(swapfile);
				logme(concat('Swapped to this logfile from ', conf.logfile, ' on ', DateTimeToStr(Now())), 2);
				chdir(conf.chroot);
				end;
			end;
		end;
	end;

{******************************************************no*hidden*feature*beyond*this*line*of*code****************************************************}

procedure treatEE();															{AESTER EEG^^}
	begin
	send('Bless you');
	send('');
	CloseConnection();
	end;

{******************************************************no*hidden*feature*above*this*line*of*code*****************************************************}

procedure treatGET();
	var
		tmpreq : string;
	begin						//e.g. line is 'GET /index.html HTTP/1.1'
	logme('Request:', 6);
	logme(concat('> ', line), 6);

	delete(line, 1, 4);				//e.g. line is '/index.html HTTP/1.1'
	delete(line, pos(' ', line), length(line));	//e.g. line is '/index.html'

	tmpreq := 'not empty';
	while tmpreq <> '' do
		begin
		readln(instr, tmpreq);
		logme(concat('> ', tmpreq), 6);
		end;

	LinuxPath2WinPath();                            //replaces "/" trough "\" and "%20" trough " "


	GetDirectory();					//'dir' contains the directory containing the requested file ('line' contains local filename)

	if not chgDirectory() then			//changes into directory 'dir'
	
		begin
  	      	HTTPError(404, 'Directory not found');	//send errorpage 400
  	      	CloseConnection();
        	exit();		                        //loop
        	end;

	if RootRequested() then
        	begin
        	rootElse403();                          //send errorpage 403 if there is no indexfile
        	CloseConnection();
		exit();
        	end;

	if not OpenRequest() then                       //tries to open the requested file (boolean function)
        	begin
        	HTTPError(404, 'File not found');       //sends errorpage 404
        	CloseConnection();
		exit();
        	end;

	sendRequest(200, 'OK');                         //sends headers and file
	
	CloseConnection();                              //closes connection to the client
	
	close(request);					//closes requested file
	end;

{****************************************************************************************************************************************************}

procedure ChooseWhat2Treat(line : string);
	var
		o : boolean;
	begin
	logme(concat('> ', line), 6);
	o := true;
	if ((pos('get', LowerCase(line)) = 1) AND o) then
		begin
		logme('Recognised as GET command', 4);
		treatGET();
		o := false;
		end;
	if ((pos('jeff', LowerCase(line)) = 1) AND o) then
		begin
		logme('Recognised as JEFF command', 4);
		treatJEFF();
		o := false;
		end;
	if ((pos('hatschi', LowerCase(line)) = 1) AND o) then
		begin
		logme('Recognised as sneeze', 4);
		treatEE();
		o := false;
		end;
	if o then
		begin
		HTTPError(400, 'Bad Request');          //send errorpage 400
		end;
	end;

{****************************************************************************************************************************************************}

{MAIN PROGRAM}

begin
while true do
	begin
	restart:
	vrestart := false;
	
	getInformation('jeff.conf');					//get port and IP to run server on
	
	LoadContentTypes();
	
	{OpenLogFile(conf.logfile);}					//logfile opened in 'InitialLog()'
	
	InitialLog();						//create log-entry about server start and loaded configuration
	
	initialiseSocket();                 	           	//prepare socket
	
	while true do                         		        //loop begins here
		begin
		
		flush(log);					//writebuffer rest into log file
		
		chdir(conf.chroot);
		
		Wait4Requests();                                //prepares "instr" and "outstr"
	
		readln(instr, line);
		
		ChooseWhat2Treat(line);
		
		if vrestart then				//var 'vrestart' is set in ChooseWhat2Treat->treatJEFF->action=shutdown and value=restart
			begin
			chdir(homedir);
			break;
			end;
		end;                                            //loop
	
	close(log);						//closes logfile {actually never used}
	end;
end.							//program ends here
