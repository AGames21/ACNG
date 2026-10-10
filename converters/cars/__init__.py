"""Per-car profiles for the AC car converter.

A profile is a module in this package with up to five dicts, one per converter module:
BUILD_AC_CAR, EXPORT_KN5, CAR_UPGRADES, CAR_DETAILS and CAR_SOUNDS. load() sets each entry on
its module. Only names the module already defines can be set, so a typo fails loudly instead
of silently building with the 1M default. Values may be functions (for example spec_parts).
"""
import importlib
import re
import sys
from pathlib import Path

MODULES = {'BUILD_AC_CAR': 'build_ac_car', 'EXPORT_KN5': 'export_kn5', 'CAR_UPGRADES': 'car_upgrades',
           'CAR_DETAILS': 'car_details', 'CAR_SOUNDS': 'car_sounds'}


def _module(name):
    # build_ac_car usually runs as __main__; a fresh import would be a second, unused copy.
    main = sys.modules.get('__main__')
    if main and Path(getattr(main, '__file__', '') or '').stem == name:
        return main
    return importlib.import_module(name)


def load(name):
    """Apply profile `name` (converters/cars/<name>.py) to the converter modules; returns it."""
    if not re.fullmatch(r'[a-z0-9_]+', name or ''):
        raise ValueError(f'Bad car profile name: {name!r}')
    try:
        profile = importlib.import_module(f'{__name__}.{name}')
    except ModuleNotFoundError as e:
        raise ValueError(f'No car profile {name!r} in converters/cars/') from e
    for key, module_name in MODULES.items():
        values = getattr(profile, key, {})
        module = _module(module_name)
        unknown = sorted(k for k in values if not hasattr(module, k))
        if unknown:
            raise ValueError(f'{name}.{key}: {module_name} has no {", ".join(unknown)}')
        for k, v in values.items():
            setattr(module, k, v)
    for hook in getattr(profile, 'AFTER_LOAD', ()):
        hook()
    return profile
