#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os, sys, re

sys.path.append(os.path.join("vendor", "rabbitmq-codegen"))

from amqp_codegen import *
try:
    from mako.template import Template
except ImportError:
    print "Mako isn't installed. Run easy_install mako."
    sys.exit(1)

# main class
class AmqpSpecObject(AmqpSpec):
    IGNORED_CLASSES = ["access", "tx"]
    IGNORED_FIELDS = {
        'ticket': 0,
        'nowait': 0,
        'capabilities': '',
        'insist' : 0,
        'out_of_band': '',
        'known_hosts': '',
    }

    def __init__(self, path):
        AmqpSpec.__init__(self, path)

        def extend_field(field):
            field.ruby_name = re.sub("-", "_", field.name)
            field.type = self.resolveDomain(field.domain)
            field.banned = bool(field.name in self.__class__.IGNORED_FIELDS)

        for klass in self.classes:
            klass.banned = bool(klass.name in self.__class__.IGNORED_CLASSES)

            for field in klass.fields:
                extend_field(field)

            for method in klass.methods:
                for field in method.arguments:
                    extend_field(field)

        self.classes = filter(lambda klass: not klass.banned, self.classes)

# I know, I'm a bad, bad boy, but come on guys,
# monkey-patching is just handy for this case.
# Oh hell, why Python doesn't have at least
# anonymous functions? This looks so ugly.
original_init = AmqpEntity.__init__
def new_init(self, arg):
    original_init(self, arg)
    constant_name = ""
    for chunk in self.name.split("-"):
        constant_name += chunk.capitalize()
    self.constant_name = constant_name
AmqpEntity.__init__ = new_init

# method.accepted_by("server")
# method.accepted_by("client", "server")
accepted_by_update = json.loads(file("amqp_0.9.1_changes.json").read())

def accepted_by(self, *receivers):
    def get_accepted_by(self):
        try:
            return accepted_by_update[self.klass.name][self.name]
        except KeyError:
            return ["server", "client"]

    actual_receivers = get_accepted_by(self)
    return all(map(lambda receiver: receiver in actual_receivers, receivers))

AmqpMethod.accepted_by = accepted_by

def convert_to_ruby(field):
    name = re.sub("-", "_", field.name) # TODO: use ruby_name
    if field.defaultvalue == None:
        return "%s = nil" % (name,)
    elif field.defaultvalue == False:
        return "%s = false" % (name,)
    elif field.defaultvalue == True:
        return "%s = true" % (name,)
    else:
        return "%s = %r" % (name, field.defaultvalue)

def args(self):
    buffer = []
    for f in self.arguments:
        buffer.append(convert_to_ruby(f))
    if self.hasContent:
        buffer.append("user_headers = nil")
        buffer.append("payload = \"\"")
        buffer.append("frame_size = nil")
    return buffer

AmqpMethod.args = args

def binary(self):
    method_id = self.klass.index << 16 | self.index
    return "0x%08X # %i, %i, %i" % (method_id, self.klass.index, self.index, method_id)

AmqpMethod.binary = binary

# helpers
def render(path, **context):
    file = open(path)
    template = Template(file.read())
    return template.render(**context)

def main(json_spec_path):
    spec = AmqpSpecObject(json_spec_path)
    print render("protocol.rb.pytemplate", spec = spec)

if __name__ == "__main__":
    do_main_dict({"spec": main})