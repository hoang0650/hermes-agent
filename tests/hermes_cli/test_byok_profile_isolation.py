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
        assert load_config()['model']['api_key'] == 'aimarkets-byok-required'
        assert load_config()['model']['base_url'] == 'https://byok-not-configured.invalid/v1'
    finally:
        reset_hermes_home_override(token)


def test_shared_runtime_tools_are_blocked():
    from plugins.dashboard_auth.aimarkets import _block_shared_runtime_tools

    for name in ('terminal', 'read_file', 'write_file', 'delegate_task', 'unknown_tool'):
        result = _block_shared_runtime_tools(tool_name=name, args={})
        assert result['action'] == 'block'
        assert result['message']


def test_real_registered_tool_hook_blocks_execution(monkeypatch):
    from hermes_cli import plugins
    from plugins.dashboard_auth.aimarkets import register

    monkeypatch.setenv('HERMES_AIMARKETS_API_URL', 'https://api.aimarkets.vn')
    monkeypatch.setenv('AIMARKETS_SERVICE_SECRET', 'fake-test-service-secret')
    manager = plugins.PluginManager()
    ctx = plugins.PluginContext(plugins.PluginManifest(name='byok-security-test'), manager)
    monkeypatch.setattr(ctx, 'register_dashboard_auth_provider', lambda provider: None)
    register(ctx)
    monkeypatch.setattr(plugins, '_delivery_manager', lambda: manager)
    action, message = plugins.get_pre_tool_call_directive('terminal', {'command': 'read another profile'})
    assert action == 'block'
    assert 'isolated buyer sandboxes' in message


def test_shared_runtime_rejects_new_and_existing_buyer_sessions(monkeypatch):
    import pytest
    from hermes_cli.dashboard_auth import InvalidCredentialsError, RefreshExpiredError

    monkeypatch.delenv('HERMES_AIMARKETS_TENANT_ISOLATED', raising=False)
    provider = AimarketsAuthProvider(secret=b'fake-test-signing-secret-32-bytes!!')
    old_session = provider._mint_session(user_id='a' * 24, username='test-buyer', profile='market-' + 'a' * 24)
    assert provider.verify_session(access_token=old_session.access_token) is None
    with pytest.raises(InvalidCredentialsError, match='tenant isolation'):
        provider.complete_password_login(username='test-buyer', password='not-used')
    with pytest.raises(RefreshExpiredError, match='tenant isolation'):
        provider.refresh_session(refresh_token=old_session.refresh_token)
