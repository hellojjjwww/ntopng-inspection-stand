@load base/protocols/conn
@load base/protocols/dns
@load base/protocols/http
@load base/protocols/ssl
@load base/protocols/ssh
@load policy/protocols/conn/known-hosts
@load policy/protocols/conn/known-services

redef LogAscii::use_json = T;
