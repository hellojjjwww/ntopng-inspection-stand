# @file local.zeek
# @brief Site policy for the Zeek passive traffic sensor.
# @version 1.0.0
# @license MIT

@load base/protocols/conn
@load base/protocols/dns
@load base/protocols/http
@load base/protocols/ssl
@load base/protocols/ssh
@load policy/protocols/conn/known-hosts
@load policy/protocols/conn/known-services

redef LogAscii::use_json = T;
