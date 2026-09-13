#!/usr/bin/env python3
"""Verify hierarchy through the installed CLI; only own records are soft deleted."""
import json, pathlib, subprocess, sys, uuid
cli = sys.argv[1]
prefix = 'structure-qa-' + str(uuid.uuid4())
owned = {'directions': [], 'projects': [], 'tasks': []}
def call(*args, ok=True, body=None):
    p = subprocess.run([cli, *args], input=json.dumps(body) if body else None, text=True, capture_output=True)
    r = json.loads(p.stdout)
    assert r['ok'] is ok and (p.returncode == 0) is ok, r
    return r
def rpc(command, id=None, fields=None, ok=True):
    return call('rpc', body={'command':command,'id':id,'fields':fields or {}}, ok=ok)
def create(kind, *args):
    r = call(*args)['records'][0]; owned[kind].append(r['id']); return r
try:
    d = create('directions', 'new-direction', '【验收】方向结构', '--request-id', prefix)
    assert call('new-direction', '【验收】方向结构', '--request-id', prefix)['records'][0]['id'] == d['id']
    a = create('projects', 'new-project', '【验收】专项 A', '--direction', d['id'])
    b = create('projects', 'new-project', '【验收】专项 B', '--direction', d['id'])
    assert {r['id'] for r in call('projects','--direction',d['id'])['records']} == {a['id'],b['id']}
    root = create('tasks', 'add', '【验收】无日期任务', '--project', a['id'])
    child = create('tasks', 'add', '【验收】继承归属子任务', '--parent', root['id'])
    assert 'due' not in root['fields'] and child['fields']['listID'] == a['id']
    assert {r['id'] for r in call('tasks','--direction',d['id'])['records']} == set(owned['tasks'])
    assert call('update',root['id'],'--reminder','2026-09-14',ok=False)['errorCode'] == 'unknown_option'
    assert not rpc('task.update',root['id'],{'reminder':'2026-09-14T00:00:00Z'},ok=False)['ok']
    move = call('update',root['id'],'--project',b['id'])
    assert call('get',child['id'])['records'][0]['fields']['listID'] == b['id']
    call('undo',move['eventID'])
    assert call('get',child['id'])['records'][0]['fields']['listID'] == a['id']
    call('complete',child['id'])
    assert [r['id'] for r in call('tasks','--view','completed','--direction',d['id'])['records']] == [child['id']]
    assert not call('tasks','--view','completed','--project',b['id'])['records']
    assert rpc('direction.update',d['id'],{'trashed':True},ok=False)['errorCode'] == 'direction_not_empty'
    print('PASS: installed CLI direction/project creation and scoping, idempotency, undated capture, child inheritance, subtree move and undo, completed scoping, reminder rejection')
finally:
    for id in owned['tasks']: call('trash',id)
    for id in owned['projects']: rpc('project.update',id,{'trashed':True})
    for id in owned['directions']: rpc('direction.update',id,{'trashed':True})
    if len(sys.argv)>2: pathlib.Path(sys.argv[2]).write_text(json.dumps(owned,ensure_ascii=False,indent=2))
