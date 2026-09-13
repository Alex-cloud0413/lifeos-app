#!/usr/bin/env python3
"""Exercise the live public CLI. Own test records end in recoverable Trash."""
import json, subprocess, sys, uuid, datetime
cli = sys.argv[1]
prefix = 'qa02-' + str(uuid.uuid4())
created, templates, lists, filters = [], [], [], []
def call(*args, ok=True, input=None):
    process = subprocess.run([cli, *args], input=input, capture_output=True, text=True)
    result = json.loads(process.stdout)
    assert result['ok'] is ok and (process.returncode == 0) is ok, result
    return result
def rpc(command, id=None, fields=None, ok=True, **rest):
    body = dict(command=command, fields=fields or {}, **rest)
    if id is not None: body['id'] = id
    return call('rpc', input=json.dumps(body, ensure_ascii=False), ok=ok)
def add(title, **fields):
    r = rpc('task.add', fields=dict(title=title, **fields))['records'][0]
    created.append(r['id']); return r
def fields(id): return call('get', id)['records'][0]['fields']
try:
    call('status')
    literal = '明天 09:00 【验收】CLI 任务 #验收 !1'
    result = call('add', literal, '--request-id', prefix)
    root = result['records'][0]; created.append(root['id'])
    assert root['fields']['title'] == literal and 'due' not in root['fields'] and root['fields']['priority'] == 0
    assert call('add', literal, '--request-id', prefix)['eventID'] == prefix
    revision = root['revision']
    call('update', root['id'], '--notes', '第一行\n第二行', '--revision', revision)
    assert call('update', root['id'], '--title', '不应覆盖', '--revision', revision, ok=False)['errorCode'] == 'revision_conflict'
    assert call('update', root['id'], '--due', '明天', ok=False)['errorCode'] == 'invalid_date'
    base = '2026-09-14T01:00:00Z'; end = '2026-09-14T02:00:00Z'
    group = rpc('list.add', fields={'title':'【验收】自定义分栏','sections':['准备','执行','交付']})['records'][0]['id']; lists.append(group)
    rpc('task.update', root['id'], dict(due=base,end=end,allDay=False,listID=group,tags=['验收'],section='准备',priority=3,progress=35,pinned=True))
    child = add('【验收】子任务', parentID=root['id'], listID=group, due='2026-09-15T01:00:00Z')
    batch = rpc('task.batch',fields={'ids':[root['id'],child['id']],'action':'postpone','days':2})
    assert fields(root['id'])['due'] == '2026-09-16T01:00:00.000Z'
    assert fields(root['id'])['end'] == '2026-09-16T02:00:00.000Z'
    assert rpc('task.batch',fields={'ids':[root['id'],'task:missing'],'action':'update','priority':1},ok=False)['errorCode']=='not_found'
    assert fields(root['id'])['priority']==3
    call('undo',batch['eventID']); assert fields(root['id'])['due']=='2026-09-14T01:00:00Z'
    change=rpc('task.update',root['id'],{'priority':1})
    rpc('task.update',root['id'],{'progress':65})
    call('undo',change['eventID']); assert fields(root['id'])['priority']==3 and fields(root['id'])['progress']==65
    assert call('undo',change['eventID'],ok=False)['errorCode']=='undo_conflict'
    rpc('task.reorder',fields={'ids':[child['id'],root['id']]}); assert fields(root['id'])['rank']==1024
    rpc('view.update','view:'+group,{'sort':'manual','group':'section'})
    query=dict(tags=['不存在'],priority=3,matchAny=True,excludedTags=['排除'])
    filt=rpc('filter.add',fields={'title':'【验收】组合筛选','query':json.dumps(query,ensure_ascii=False)})['records'][0]['id'];filters.append(filt)
    rpc('filter.update',filt,{'title':'【验收】已编辑筛选'})
    assert root['id'] in [r['id'] for r in rpc('task.list',filter=query)['records']]
    template=call('save-template',root['id'])['records'][0]['id'];templates.append(template)
    copied=call('use-template',template,'--anchor','2026-10-01')['records']
    copied += [r for r in call('tasks','--list',group)['records'] if r['fields'].get('parentID')==copied[0]['id']]
    created.extend(r['id'] for r in copied)
    assert len(copied)==2 and copied[1]['fields']['parentID']==copied[0]['id']
    assert copied[0]['fields']['due'].startswith('2026-10-01T01:00') and copied[1]['fields']['due'].startswith('2026-10-02T01:00')
    duplicate=call('duplicate',root['id'])['records']
    duplicate += [r for r in call('tasks','--list',group)['records'] if r['fields'].get('parentID')==duplicate[0]['id']]
    created.extend(r['id'] for r in duplicate)
    assert len(duplicate)==2
    call('convert',duplicate[0]['id'],'--type','note'); note=fields(duplicate[0]['id']);assert note['due'] is None and note['itemType']=='note'
    assert call('complete',duplicate[0]['id'],ok=False)['errorCode']=='is_note'
    assert duplicate[0]['id'] in [r['id'] for r in call('tasks','--view','notes')['records']]
    assert call('link',root['id'])['message'].startswith('dayline://task?id=')
    history=json.loads(call('history',root['id'],'--limit','2')['message']);assert len(history)==2 and 'id' in history[0]
    rpc('status',version=99,ok=False)
    repeat=add('【验收】每周重复',due=base,recurrence='weekly',progress=90)
    completed=call('complete',repeat['id'])['records'];successor=completed[1]['id'];created.append(successor)
    assert fields(successor)['progress']==0
    call('trash',successor);call('restore',successor);assert not fields(successor)['trashed']
    assert call('stats',ok=False)['errorCode']=='unknown_command'
    assert rpc('stats',ok=False)['errorCode']=='unknown_command'
    print('PASS: literal capture, explicit dates, idempotency, conflict protection, atomic batch/postpone/undo, ordering, sections, filters/edit, templates/tree, note conversion, links, paginated history, recurrence, progress, removed statistics rejected')
finally:
    for record_id in created: call('trash',record_id)
    for record_id in templates: rpc('template.trash',record_id)
    for record_id in filters: rpc('filter.update',record_id,{'trashed':True})
    for record_id in lists: rpc('list.update',record_id,{'trashed':True})
