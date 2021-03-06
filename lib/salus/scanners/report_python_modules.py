import json

try: # for pip >= 10
    from pip._internal.req import parse_requirements
except ImportError: # for pip <= 9.0.3
    from pip.req import parse_requirements

deps = parse_requirements('requirements.txt', session="_")

dependencies = {}

for dependency in deps:
    if hasattr(dependency.req, 'key'):
      dependencies[dependency.req.key] = str(dependency.req.specifier)
    else:
      dependencies[dependency.req.name] = str(dependency.req.specifier)

print(json.dumps(dependencies))
