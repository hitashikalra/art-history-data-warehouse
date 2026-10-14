-- Every century's medium shares should add up to ~100%.
-- Returns rows (= test failure) for any century that's off by more than 0.5.

select century, sum(share_of_century_pct) as total_pct
from {{ ref('mart_medium_by_century') }}
group by century
having abs(sum(share_of_century_pct) - 100) > 0.5
