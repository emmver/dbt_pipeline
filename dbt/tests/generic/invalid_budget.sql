{% test invalid_budget(model, column_name) %}
select *
from {{ model }}
where try_cast({{ column_name }} as decimal(12, 2)) is null
   or try_cast({{ column_name }} as decimal(12, 2)) < 0
{% endtest %}