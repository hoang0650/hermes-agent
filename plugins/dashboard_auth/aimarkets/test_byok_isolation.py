import ast,contextvars,os,pathlib,sys,tempfile,types,unittest
from concurrent.futures import ThreadPoolExecutor
SOURCE=pathlib.Path(__file__).parent/'__init__.py'
tree=ast.parse(SOURCE.read_text());cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='AimarketsAuthProvider');names={'_PLATFORM_KEY_NAMES','_BUYER_ENV','_read_env_file','_apply_buyer_credentials'};body=[n for n in cls.body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) and n.name in names or isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id in names for t in n.targets)];mod=ast.Module(body=[ast.ClassDef(name=cls.name,bases=[],keywords=[],body=body,decorator_list=[])],type_ignores=[]);ast.fix_missing_locations(mod)
class Isolation(unittest.TestCase):
 def test_profiles_do_not_modify_global_environment_or_reuse_removed_keys(self):
  with tempfile.TemporaryDirectory() as root:
   home=contextvars.ContextVar('home');cfg={};connections={};ids=['a'*24,'b'*24];sentinel='platform-sentinel';old=os.environ.get('OPENAI_API_KEY');os.environ['OPENAI_API_KEY']=sentinel
   profiles=types.ModuleType('hermes_cli.profiles');profiles.get_profile_dir=lambda p:pathlib.Path(root)/p
   config=types.ModuleType('hermes_cli.config');config.load_config=lambda:cfg.get(home.get(),{}).copy();config.save_config=lambda c:cfg.__setitem__(home.get(),c)
   constants=types.ModuleType('hermes_constants');constants.get_hermes_home=lambda:root;constants.set_hermes_home_override=home.set;constants.reset_hermes_home_override=home.reset
   package=types.ModuleType('hermes_cli');package.profiles=profiles
   sys.modules.update({'hermes_cli':package,'hermes_cli.profiles':profiles,'hermes_cli.config':config,'hermes_constants':constants})
   ns={'os':os,'re':__import__('re'),'logger':__import__('logging').getLogger(__name__)};exec(compile(mod,str(SOURCE),'exec'),ns);provider=ns['AimarketsAuthProvider'];provider._fetch_buyer_connection=staticmethod(lambda uid:connections.get(uid))
   for uid in ids:connections[uid]={'provider':'openai','apiKey':'fake-key-'+uid,'baseUrl':'https://api.openai.com/v1','model':'test'}
   try:
    with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(lambda uid:provider._apply_buyer_credentials('market-'+uid),ids))
    self.assertEqual(os.environ['OPENAI_API_KEY'],sentinel)
    for uid in ids:
     text=(pathlib.Path(root)/('market-'+uid)/'.env').read_text();self.assertIn('fake-key-'+uid,text);self.assertNotIn('fake-key-'+next(i for i in ids if i!=uid),text);self.assertEqual((pathlib.Path(root)/('market-'+uid)/'.env').stat().st_mode&0o777,0o600)
    connections.pop(ids[0]);provider._apply_buyer_credentials('market-'+ids[0]);self.assertNotIn('fake-key-',(pathlib.Path(root)/('market-'+ids[0])/'.env').read_text());self.assertNotIn('api_key',cfg[str(pathlib.Path(root)/('market-'+ids[0]))]['model'])
   finally:
    if old is None:os.environ.pop('OPENAI_API_KEY',None)
    else:os.environ['OPENAI_API_KEY']=old
if __name__=='__main__':unittest.main()
