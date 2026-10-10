import unittest
import backend as b

class Tests(unittest.TestCase):
    def record(self, pid, name, parent=0, ticks=0, start=1, pss=1024):
        return dict(pid=pid, name=name, comm=name, ppid=parent, ticks=ticks, start=start, rss=4096, pss=pss)

    def test_cpu_capacity_and_iowait(self):
        self.assertEqual(b.cpu_percent((100,40),(200,90)),50)
        self.assertIsNone(b.cpu_percent((100,40),(100,40)))

    def test_stat_name_with_parentheses(self):
        fields=['S','1']+['0']*22
        fields[11],fields[12],fields[19],fields[21]='12','3','123','2'
        p=b.parse_stat('99 (name (helper)) '+' '.join(fields))
        self.assertEqual(p['comm'],'name (helper)')
        self.assertEqual(p['ticks'],15)
        self.assertEqual(p['start'],123)
        self.assertEqual(p['rss'],2*b.PAGE)

    def test_vivaldi_helpers_merge_btop_rss_and_retain_pss(self):
        records={1:self.record(1,'vivaldi-bin',ticks=b.HZ),2:self.record(2,'vivaldi-bin',1,ticks=b.HZ),3:self.record(3,'chrome_crashpad_handler',1,ticks=b.HZ)}
        old={pid:dict(p,ticks=0) for pid,p in records.items()}
        groups=b.group_processes(records,old,1,4)
        self.assertEqual(len(groups),1)
        self.assertEqual(groups[0]['name'],'Vivaldi')
        self.assertEqual(groups[0]['count'],3)
        self.assertEqual(groups[0]['cpu'],75)
        self.assertEqual(groups[0]['memory'],12288)
        self.assertEqual(groups[0]['rss'],12288)
        self.assertEqual(groups[0]['pss'],3072)

    def test_pid_reuse_does_not_spike(self):
        p=self.record(1,'example',ticks=100000,start=2,pss=None)
        groups=b.group_processes({1:p},{1:dict(p,ticks=0,start=1)},1,4)
        self.assertEqual(groups[0]['cpu'],0)
        self.assertEqual(groups[0]['memory'],4096)
        self.assertEqual(groups[0]['rss_fallback'],1)

    def test_incomplete_pss_is_unavailable_not_rss(self):
        records={1:self.record(1,'vivaldi-bin',pss=1024),2:self.record(2,'vivaldi-bin',1,pss=None)}
        group=b.group_processes(records,{},1,4)[0]
        self.assertEqual(group['memory'],8192)
        self.assertEqual(group['rss'],8192)
        self.assertIsNone(group['pss'])
        self.assertEqual(group['rss_fallback'],1)

    def test_pss_zero_is_not_replaced_with_rss(self):
        p=self.record(1,'example',pss=0)
        group=b.group_processes({1:p},{},1,4)[0]
        self.assertEqual(group['rss'],4096)
        self.assertEqual(group['pss'],0)
        self.assertEqual(group['rss_fallback'],0)

    def test_network_reset(self):
        self.assertEqual(b.rates({'eth0':(200,200)},{'eth0':(100,300)},2),[dict(name='eth0',read=0,write=50)])

    def test_closed_does_not_scan_processes(self):
        from unittest.mock import patch
        sampler=b.Sampler()
        with patch.object(b,'process_records',side_effect=AssertionError('unexpected scan')):
            result=sampler.sample(False)
        self.assertFalse(result['detailed'])
        self.assertNotIn('apps',result)
        self.assertTrue(0 <= result['memory']['percent'] <= 100)

if __name__=='__main__':
    unittest.main()
