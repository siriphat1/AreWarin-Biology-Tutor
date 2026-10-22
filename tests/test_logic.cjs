const fs=require('node:fs');const assert=require('node:assert/strict');const vm=require('node:vm');const path=require('node:path');
const base=path.join(__dirname,'..');
const js=fs.readFileSync(path.join(base,'tutor-os/attendance-os.js'),'utf8');
const html=fs.readFileSync(path.join(base,'tutor-os/index.html'),'utf8');
const sql=fs.readFileSync(path.join(base,'sql/01_attendance_migration.sql'),'utf8');
const window={};const document={readyState:'loading',addEventListener(){}};
vm.runInNewContext(js,{window,document,crypto:{randomUUID:()=> '00000000-0000-4000-8000-000000000001'},Intl,Date,console,setTimeout,URL,Blob});
const diff=window.AreWarinAttendance.minutesBetween;
for(const [a,b,expected] of [
 ['17:00','18:30',90],['18:25','20:00',95],['23:00','23:59',59],
 ['00:00','01:00',60],['10:00','10:00',0],['21:00','00:00',0],
 ['08:00','20:00',0],['11:40','12:10',30],['99:99','00:00',0],
 ['', '11:00',0],['09:00','09:01',1]
])assert.equal(diff(a,b),expected,`${a}-${b}`);
for(const text of ['id="awosAttendanceNav"','id="section-attendance"','./attendance-os.js','./app.js','../config.js'])assert.ok(html.includes(text),`index.html missing ${text}`);
for(const name of ['awos_bootstrap','awos_save_records','awos_update_record','awos_delete_record','awos_roster_upsert','awos_access_upsert','awos_catalog','awos_student_no_overlap'])assert.ok(sql.includes(name),`SQL missing ${name}`);
assert.ok(sql.includes('security definer set search_path=\'\''),'functions should pin search_path');
assert.ok(sql.includes('create policy awos_attendance_read'),'RLS missing');
assert.ok(sql.includes('revoke all on public.awos_access'),'table write revoke missing');
assert.ok(!sql.toLowerCase().includes('drop table public.students'),'must not drop legacy students');
console.log('PASS: 11 time tests, HTML integration markers, SQL security and RPC presence');
