"""Deploy the prepared ASP.NET Core publish directory over certificate-validated FTPS.

Run Prepare-Publish.ps1 first. This script never prints credentials or uploads
source .local settings, Android signing material, or the FTP password.
"""
import ftplib
import io
import json
import ssl
import hashlib
from pathlib import Path

class CompatibleFtpTls(ftplib.FTP_TLS):
    def storbinary(self,cmd,fp,blocksize=65536,callback=None,rest=None):
        # IIS can wait for data-socket EOF before completing the TLS shutdown.
        # Closing this already certificate-validated TLS socket avoids a shutdown
        # deadlock. The control and data channels remain encrypted and verified.
        self.voidcmd('TYPE I')
        with self.transfercmd(cmd,rest) as connection:
            while True:
                block=fp.read(blocksize)
                if not block:break
                connection.sendall(block)
                if callback:callback(block)
        return self.voidresp()

root=Path(__file__).resolve().parent.parent
settings=json.loads((root/'.local/secrets.json').read_text(encoding='utf-8-sig'))
hosting=settings['Hosting']
publish=root/'.local/publish'
if not (publish/'Attendance.Api.dll').exists() or not (publish/'appsettings.Production.json').exists():
    raise SystemExit('Prepare-Publish.ps1 must complete first.')
site=hosting['SiteFolder']
if not site or '/' in site or '\\' in site or site in ('.','..'):
    raise SystemExit('Invalid site folder.')
files=sorted((p for p in publish.rglob('*') if p.is_file()),key=lambda p:(p.name=='web.config',str(p)))
hashes={p.relative_to(publish).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest_path=root/'.local/deployment-manifest.json'
previous=json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {}
old_hashes=previous.get('files',{}) if previous.get('host')==hosting['FtpHost'] and previous.get('site')==site else {}
changed=[p for p in files if old_hashes.get(p.relative_to(publish).as_posix())!=hashes[p.relative_to(publish).as_posix()]]
if not changed:raise SystemExit('No application files changed since the successful deployment.')
with CompatibleFtpTls(context=ssl.create_default_context(),timeout=45) as ftp:
    ftp.connect(hosting['FtpHost'],21)
    ftp.login(hosting['FtpUsername'],hosting['FtpPassword'])
    ftp.prot_p()
    ftp.cwd(site)
    remote_root=ftp.pwd().rstrip('/')
    ftp.storbinary('STOR app_offline.htm',io.BytesIO('API đang được cập nhật. Vui lòng thử lại sau ít phút.'.encode('utf-8')))
    count=0
    for path in changed:
        relative=path.relative_to(publish)
        ftp.cwd(remote_root)
        for part in relative.parts[:-1]:
            try:ftp.mkd(part)
            except ftplib.error_perm as ex:
                if not str(ex).startswith('550'):raise
            ftp.cwd(part)
        if not (ftp.pwd()==remote_root or ftp.pwd().startswith(remote_root+'/')):
            raise RuntimeError('Remote path escaped the intended website folder.')
        with path.open('rb') as stream:ftp.storbinary('STOR '+path.name,stream)
        count+=1
        if ftp.size(path.name)!=path.stat().st_size:raise RuntimeError('Uploaded file size verification failed.')
        if count%10==0 or count==len(changed):print(f'Uploaded {count}/{len(changed)} changed application files.',flush=True)
    ftp.cwd(remote_root)
    ftp.delete('app_offline.htm')
manifest_path.write_text(json.dumps({'host':hosting['FtpHost'],'site':site,'files':hashes}),encoding='utf-8')
print(f'FTPS deployment completed: {len(changed)} changed files. Verify HTTPS endpoints before marking complete.')
