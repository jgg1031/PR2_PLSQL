DROP TABLE detalle_pedido CASCADE CONSTRAINTS;
DROP TABLE pedidos CASCADE CONSTRAINTS;
DROP TABLE platos CASCADE CONSTRAINTS;
DROP TABLE personal_servicio CASCADE CONSTRAINTS;
DROP TABLE clientes CASCADE CONSTRAINTS;

DROP SEQUENCE seq_pedidos;


-- Creación de tablas y secuencias



CREATE SEQUENCE seq_pedidos
    START WITH 1       -- Empieza desde 1
    INCREMENT BY 1     -- Aumenta de 1 en 1
    NOMAXVALUE         -- Sin límite máximo
    NOCYCLE            -- No se reinicia
    CACHE 20;          -- Guarda 20 valores en caché para optimizar rendimiento

CREATE TABLE clientes (
    id_cliente INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    telefono VARCHAR2(20)
);

CREATE TABLE personal_servicio (
    id_personal INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    pedidos_activos INTEGER DEFAULT 0 CHECK (pedidos_activos <= 5)
);

CREATE TABLE platos (
    id_plato INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    precio DECIMAL(10, 2) NOT NULL,
    disponible INTEGER DEFAULT 1 CHECK (DISPONIBLE in (0,1))
);

CREATE TABLE pedidos (
    id_pedido INTEGER PRIMARY KEY,
    id_cliente INTEGER REFERENCES clientes(id_cliente),
    id_personal INTEGER REFERENCES personal_servicio(id_personal),
    fecha_pedido DATE DEFAULT SYSDATE,
    total DECIMAL(10, 2) DEFAULT 0
);

CREATE TABLE detalle_pedido (
    id_pedido INTEGER REFERENCES pedidos(id_pedido),
    id_plato INTEGER REFERENCES platos(id_plato),
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_pedido, id_plato)
);


	
-- Procedimiento a implementar para realizar la reserva
create or replace procedure registrar_pedido(
    arg_id_cliente      INTEGER, 
    arg_id_personal     INTEGER, 
    arg_id_primer_plato INTEGER DEFAULT NULL,
    arg_id_segundo_plato INTEGER DEFAULT NULL
) is 
    --EXCEPCIONES
    --Mensajes de excepciones
    msg_plato_no_disponible constant varchar(50) := 'Uno de los plato seleccionado no está disponible';
    msg_pedido_sin_platos constant varchar(50) := 'El pedido debe contener al menos un plato';
    msg_personal_ocupado constant varchar(50) := 'El personal de servicio tiene demasiados pedidos';
    msg_plato_inexistente_plato1 constant varchar(50) := 'El primer plato seleccionado no existe';
    msg_plato_inexistente_plato2 constant varchar(50) := 'El segundo plato seleccionado no existe';
    
    --Declaración de excepciones P4.5 (uso de excepciones propias)
    plato_no_disponible exception;
    pragma exception_init(plato_no_disponible, -20001);
    pedido_sin_platos exception;
    pragma exception_init(pedido_sin_platos, -20002);
    personal_ocupado exception;
    pragma exception_init(personal_ocupado, -20003);
    plato_inexistente exception;
    pragma exception_init(plato_inexistente, -20004);
    
    --VARIABLES    
    --Declaración de cursores
    CURSOR vPlato1Disponible IS 
        SELECT id_plato, disponible FROM platos WHERE id_plato = arg_id_primer_plato;
    
    CURSOR vPlato2Disponible IS
        SELECT id_plato, disponible FROM platos WHERE id_plato = arg_id_segundo_plato;

    --Declaración de variables
    varIdPlato1 platos.id_plato%type;
    varPlatoDisponible1 platos.disponible%type;
    varIdPlato2 platos.id_plato%type;
    varPlatoDisponible2 platos.disponible%type;
    varPersonalDisponible personal_servicio.pedidos_activos%type;
    varTotalPedido PEDIDOS.total%type;
    var_id_pedido PEDIDOS.id_pedido%type;
    
 begin
    
    -- Comprobar que al menos un plato ha sido seleccionado
    IF arg_id_primer_plato IS NULL AND arg_id_segundo_plato IS NULL THEN
        RAISE pedido_sin_platos;
    END IF;

    -- Verificar disponibilidad del primer plato
    IF arg_id_primer_plato IS NOT NULL THEN
        OPEN vPlato1Disponible;
        FETCH vPlato1Disponible INTO varIdPlato1, varPlatoDisponible1;
        CLOSE vPlato1Disponible;

        IF varIdPlato1 IS NULL THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20004, msg_plato_inexistente_plato1);
        END IF;

        IF varPlatoDisponible1 = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, msg_plato_no_disponible);
        END IF;
    END IF;

    -- Verificar disponibilidad del segundo plato
    IF arg_id_segundo_plato IS NOT NULL THEN
        OPEN vPlato2Disponible;
        FETCH vPlato2Disponible INTO varIdPlato2, varPlatoDisponible2;
        CLOSE vPlato2Disponible;

        IF varIdPlato2 IS NULL THEN
            ROLLBACK;
            RAISE_APPLICATION_ERROR(-20004, msg_plato_inexistente_plato2);
        END IF;

        IF varPlatoDisponible2 = 0 THEN
            RAISE_APPLICATION_ERROR(-20001, msg_plato_no_disponible);
        END IF;
    END IF;

    -- Verificar disponibilidad del personal de servicio
    SELECT pedidos_activos INTO varPersonalDisponible 
    FROM personal_servicio 
    WHERE id_personal = arg_id_personal
    FOR UPDATE;

    IF varPersonalDisponible >= 5 THEN
        RAISE personal_ocupado;
    END IF;
    
    -- Obtener ID del pedido
    var_id_pedido := seq_pedidos.NEXTVAL;

    -- Calcular total del pedido
    SELECT COALESCE(SUM(precio), 0) INTO varTotalPedido 
    FROM platos 
    WHERE id_plato IN (arg_id_primer_plato, arg_id_segundo_plato);

    -- Insertar el pedido
    INSERT INTO pedidos (id_pedido, id_cliente, id_personal, fecha_pedido, total) 
    VALUES (var_id_pedido, arg_id_cliente, arg_id_personal, SYSDATE, varTotalPedido);

    -- Insertar detalles del pedido (solo si los platos no son NULL)
    IF arg_id_primer_plato IS NOT NULL THEN
        INSERT INTO detalle_pedido (id_pedido, id_plato, cantidad) 
        VALUES (var_id_pedido, arg_id_primer_plato, 1);
    END IF;

    IF arg_id_segundo_plato IS NOT NULL THEN
        INSERT INTO detalle_pedido (id_pedido, id_plato, cantidad) 
        VALUES (var_id_pedido, arg_id_segundo_plato, 1);
    END IF;

    -- Actualizar pedidos activos del personal
    UPDATE personal_servicio 
    SET pedidos_activos = pedidos_activos + 1 
    WHERE id_personal = arg_id_personal;

    COMMIT;
  
  EXCEPTION
    WHEN pedido_sin_platos THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20002, msg_pedido_sin_platos);

    WHEN plato_no_disponible THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20001, msg_plato_no_disponible);

    WHEN personal_ocupado THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20003, msg_personal_ocupado);
    
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20099, 'Error inesperado: ' || SQLERRM);
        
end;
/

------ Deja aquí tus respuestas a las preguntas del enunciado:
-- NO SE CORREGIRÁN RESPUESTAS QUE NO ESTÉN AQUÍ (utiliza el espacio que necesites apra cada una)
-- * P4.1
--  Para garantizar que un miembro del personal no supera el límite de pedidos activos lo definimos en el procedimiento 'registrar_pedido'. Antes de registrar el pedido se verifica cuantos pedidos activos tiene el miembro del personal, si es mayor a 5 se lanza una excepción que impide la asignacion del pedido. 

-- * P4.2
--  Para evitar este suceso, utilizaremos una cláusula (SELECT ... FOR UPDATE) en la comprobación de la disponibilidad del peronal. 
--  De esta manera se bloquea la fila del personal de servicio evitando que otro proceso modifique 'pedidos_activos' simultanea.

-- * P4.3
--  

-- * P4.4
-- Si se añade `CHECK (pedidos_activos <= 5)`, la base de datos bloqueará valores inválidos, pero el procedimiento debe capturar el error. Por ejemplo, con `pedidos_activos = 0`, 
-- los primeros pedidos se aceptan, pero al intentar un sexto, la restricción fallará. Para controlarlo, se debe capturar la excepción y lanzar `raise_application_error(-20003)`, 
-- asegurando un manejo adecuado en PL/SQL.

-- * P4.5
-- En el código se usa programación defensiva, lo que significa que primero se hacen varias validaciones antes de modificar la base de datos, por ejemplo, 
-- se revisa que los platos estén disponibles antes de agregarlos al pedido, que el personal no tenga más de 5 pedidos activos y que al menos se haya seleccionado un plato
-- (pedido_sin_platos). También se aplican transacciones y manejo de excepciones, lo que ayuda a evitar errores y mantener la base de datos en orden, si algo falla, 
-- se usa ROLLBACK para que los datos no queden en un estado incorrecto; además, hay excepciones específicas (plato_no_disponible, pedido_sin_platos, personal_ocupado, plato_inexistente)
-- que permiten controlar mejor los errores y RAISE_APPLICATION_ERROR para mostrar mensajes claros cuando ocurre un problema.



create or replace
procedure reset_seq( p_seq_name varchar )
is
    l_val number;
begin
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || 
                                                          ' minvalue 0';
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';

end;
/


create or replace procedure inicializa_test is
begin
    
    reset_seq('seq_pedidos');
        
  
    delete from Detalle_pedido;
    delete from Pedidos;
    delete from Platos;
    delete from Personal_servicio;
    delete from Clientes;
    
    -- Insertar datos de prueba
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (1, 'Pepe', 'Perez', '123456789');
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (2, 'Ana', 'Garcia', '987654321');
    
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (1, 'Carlos', 'Lopez', 0);
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (2, 'Maria', 'Fernandez', 5);
    
    insert into Platos (id_plato, nombre, precio, disponible) values (1, 'Sopa', 10.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (2, 'Pasta', 12.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (3, 'Carne', 15.0, 0);

    commit;
end;
/




exec inicializa_test;

-- Completa lost test, incluyendo al menos los del enunciado y añadiendo los que consideres necesarios

create or replace procedure test_registrar_pedido is
begin
	 
  --caso 1 Pedido correct, se realiza
  
  -- Idem para el resto de casos

  /* - Si se realiza un pedido vac´ıo (sin platos) devuelve el error -200002.
     - Si se realiza un pedido con un plato que no existe devuelve en error -20004.
     - Si se realiza un pedido que incluye un plato que no est´a ya disponible devuelve el error -20001.
     - Personal de servicio ya tiene 5 pedidos activos y se le asigna otro pedido devuelve el error -20003
     - ... los que os puedan ocurrir que puedan ser necesarios para comprobar el correcto funcionamiento del procedimiento
*/
    --Test1: Plato no disponible Err: -20001
    begin
        inicializa_test;
        dbms_output.put_line('');
        dbms_output.put_line('Test1: Un plato no está disponible');
        registrar_pedido(1,1,2,3);
        commit;
        dbms_output.put_line('MAL: Plato no disponible usado.');
        exception
            when others then
                if SQLCODE = -20001 then
                    dbms_output.put_line('BIEN: Plato no usado exitosamente.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                else
                    dbms_output.put_line('MAL: Da error pero no detecta que el plato no está disponible.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                end if;
    end;
    
    --Test2: Plato no disponible Err: -20002
    begin
        inicializa_test;
        dbms_output.put_line('');
        dbms_output.put_line('Test2: El pedido tiene que contener al menos un plato');
        registrar_pedido(1,1,null,null);
        commit;
        dbms_output.put_line('MAL: El pedido usa platos sin id.');
        exception
            when others then
                if SQLCODE = -20002 then
                    dbms_output.put_line('BIEN: Plato no usado exitosamente.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                else
                    dbms_output.put_line('MAL: Da error pero no detecta que el plato no es nulo.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                end if;
    end;
    
    --Test3: Personal con demasiados pedidos Err: -20003
    begin
        inicializa_test;
        dbms_output.put_line('');
        dbms_output.put_line('Test3: Personal de servicio con demasiados pedidos');
        registrar_pedido(1,2,1,2);
        commit;
        dbms_output.put_line('MAL: El pedido usa un personal que no está disponible.');
        exception
            when others then
                if SQLCODE = -20003 then
                    dbms_output.put_line('BIEN: El personal no es usado correctamente.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                else
                    dbms_output.put_line('MAL: Da error pero no detecta que el personal no se puede usar.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                end if;
    end;
    
    --Test4: Primer plato no existe Err: -20004
    
    
    --Test5: Primer plato no existe Err: -20004
    begin
        inicializa_test;
        dbms_output.put_line('');
        dbms_output.put_line('Test5: Segundo plato no existe-----');
        registrar_pedido(1,1,2,4);
        commit;
        dbms_output.put_line('MAL: El pedido usa un segundo plato que no existe.');
        exception
            when others then
                if SQLCODE = -20004 then
                    dbms_output.put_line('BIEN: El segunod plato no se usa correctamente.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                else
                    dbms_output.put_line('MAL: Da error pero no detecta que el segundo plato no existe.');
                    dbms_output.put_line('Error nro ' || SQLCODE);
                    dbms_output.put_line('Mensaje ' || SQLERRM);
                end if;
    end;
    
    --Test6: El pedido se hace correctamente
    begin
        inicializa_test;
        dbms_output.put_line('');
        dbms_output.put_line('Test6: Pedido exitoso-----');
        registrar_pedido(1,1,1,2);
        commit;
        dbms_output.put_line('BIEN: El pedido se realiza con éxito.');
        exception
            when others then
                dbms_output.put_line('MAL: Da error en la inserción del pedido.');
                dbms_output.put_line('Error nro ' || SQLCODE);
                dbms_output.put_line('Mensaje ' || SQLERRM);
    end;
    
  
end;
/


set serveroutput on;
exec test_registrar_pedido;


