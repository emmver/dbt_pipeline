{% test hours_in_range(model, column_name) %}
select *
from {{ model }}
where try_cast({{ column_name }} as double) is null
   or try_cast({{ column_name }} as double) <= 0
   or try_cast({{ column_name }} as double) > 24
{% endtest %}