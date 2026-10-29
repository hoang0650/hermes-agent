import os
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from hermes_cli import profiles
from hermes_cli.config import load_config
from hermes_constants import reset_hermes_home_override, set_hermes_home_override
from plugins.dashboard_auth.aimarkets import AimarketsAuthProvider


def test_buyer_keys_use_real_profile_files_without_global_environment_mutation(tmp_path, monkeypatch):
    monkeypatch.setattr(Path, 'home', lambda: tmp_path)
    monkeypatch.setenv('HERMES_HOME', str(tmp_path / '.hermes'))
    monkeypatch.setenv('OPENAI_API_KEY', 'root-key-sentinel')
    users = ['a' * 24, 'b' * 24]
    connections = {uid: {'provider': 'openai', 'apiKey': 'fake-buyer-' + uid,
                         'baseUrl': 'https://api.openai.com/v1', 'model': 'test-model'} for uid in users}
    monkeypatch.setattr(AimarketsAuthProvider, '_fetch_buyer_connection', staticmethod(connections.get))
    with ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(lambda uid: AimarketsAuthProvider._apply_buyer_credentials('market-' + uid), users))
    assert os.environ['OPENAI_API_KEY'] == 'root-key-sentinel'
    for uid in users:
        profile_dir = profiles.get_profile_dir('market-' + uid)
        text = (profile_dir / '.env').read_text()
        assert 'fake-buyer-' + uid in text
        assert 'fake-buyer-' + next(other for other in users if other != uid) not in text
        assert (profile_dir / '.env').stat().st_mode & 0o777 == 0o600
        token = set_hermes_home_override(profile_dir)
        try:
            assert load_config()['model']['api_key'] == 'fake-buyer-' + uid
        finally:
            reset_hermes_home_override(token)
    connections.pop(users[0])
    AimarketsAuthProvider._apply_buyer_credentials('market-' + users[0])
    profile_dir = profiles.get_profile_dir('market-' + users[0])
    assert 'fake-buyer-' not in (profile_dir / '.env').read_text()
    token = set_hermes_home_override(profile_dir)
    try:
        assert 'api_key' not in load_config()['model']
    finally:
        reset_hermes_home_override(token)
